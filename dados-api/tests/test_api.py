"""Testes do gateway OData contra o Postgres (rodar num container na rede do compose; ver README da plataforma)."""
import os
import time

os.environ.update(ENTRA_TENANT_ID="tenant-teste", ENTRA_AUDIENCE="https://dados-api.bomgado.net",
                  PAGE_SIZE="1000")

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

import app as api

CHAVE = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class ChaveFalsa:
    key = CHAVE.public_key()


api.jwks.get_signing_key_from_jwt = lambda token: ChaveFalsa()
cliente = TestClient(api.app)


def token(aud="https://dados-api.bomgado.net", iss="https://sts.windows.net/tenant-teste/", grupos=None, chave=CHAVE):
    claims = {"aud": aud, "iss": iss, "exp": int(time.time()) + 600, "upn": "teste@bomgado.com"}
    if grupos is not None:
        claims["groups"] = grupos
    return {"Authorization": "Bearer " + jwt.encode(claims, chave, algorithm="RS256")}


def sql(q, p=()):
    with api.conectar() as c, c.cursor() as cur:
        cur.execute(q, p)
        return cur.fetchall()


def test_sem_token_pede_login_do_entra():
    r = cliente.get("/odata/")
    assert r.status_code == 401
    assert 'authorization_uri="https://login.microsoftonline.com/tenant-teste/oauth2/authorize"' in r.headers["www-authenticate"]


@pytest.mark.parametrize("kw", [dict(aud="https://outra-api"), dict(iss="https://sts.windows.net/outro-tenant/"),
                                dict(chave=rsa.generate_private_key(public_exponent=65537, key_size=2048))])
def test_token_invalido_e_recusado(kw):
    assert cliente.get("/odata/", headers=token(**kw)).status_code == 401


def test_grupo_obrigatorio(monkeypatch):
    monkeypatch.setattr(api, "GRUPO", "grupo-ok")
    assert cliente.get("/odata/", headers=token(grupos=["outro"])).status_code == 403
    assert cliente.get("/odata/", headers=token(grupos=["grupo-ok"])).status_code == 200


def test_lista_so_views():
    nomes = [v["name"] for v in cliente.get("/odata/", headers=token()).json()["value"]]
    assert "vw_vendas_item" in nomes
    assert all(n.startswith("vw_") for n in nomes)


def test_metadata_tipos():
    x = cliente.get("/odata/$metadata", headers=token()).text
    assert '<EntityType Name="vw_vendas_item"><Key><PropertyRef Name="id"/></Key>' in x
    assert '<Property Name="data" Type="Edm.Date"/>' in x
    assert 'Name="valor_total" Type="Edm.Decimal"' in x


def test_tabela_crua_e_directus_nao_expostas():
    for nome in ("adm04_perfil", "directus_users", "vw_x; DROP TABLE y"):
        assert cliente.get(f"/odata/{nome}", headers=token()).status_code == 404


def test_filtro_e_contagem_batem_com_sql():
    r = cliente.get("/odata/vw_vendas_item", headers=token(), params={
        "$filter": "data ge 2026-07-01 and filial eq 'BOM KAFE' and contains(mercadoria,'CAFE')",
        "$count": "true", "$top": "5", "$select": "data,mercadoria,valor_total"}).json()
    esperado = sql("SELECT count(*) n FROM api.vw_vendas_item WHERE data >= '2026-07-01' AND filial = 'BOM KAFE' "
                   "AND mercadoria ILIKE '%%CAFE%%'")[0]["n"]
    assert r["@odata.count"] == esperado > 0
    assert len(r["value"]) == 5
    assert set(r["value"][0]) == {"id", "data", "mercadoria", "valor_total"}


def test_funcoes_de_data_e_null():
    r = cliente.get("/odata/vw_vendas_item", headers=token(), params={
        "$filter": "year(data) eq 2025 and month(data) eq 12 and classificacao ne null", "$count": "true", "$top": "1"}).json()
    esperado = sql("SELECT count(*) n FROM api.vw_vendas_item WHERE EXTRACT(YEAR FROM data)=2025 AND EXTRACT(MONTH FROM data)=12 AND classificacao IS NOT NULL")[0]["n"]
    assert r["@odata.count"] == esperado


def test_paginacao_por_chave_sem_repetir():
    url, ids = "/odata/vw_vendas_item", []
    params = {"$filter": "data ge 2026-01-01", "$select": "id"}
    for _ in range(3):
        r = cliente.get(url, headers=token(), params=params).json()
        ids += [v["id"] for v in r["value"]]
        url, params = r["@odata.nextLink"].split("/odata", 1)[1], None
        url = "/odata" + url
    assert len(ids) == 3000 == len(set(ids))
    assert ids == sorted(ids)


def test_orderby_com_offset():
    r = cliente.get("/odata/vw_vendas_item", headers=token(), params={"$orderby": "valor_total desc", "$top": "3"}).json()
    valores = [v["valor_total"] for v in r["value"]]
    assert valores == sorted(valores, reverse=True)
    assert "@odata.nextLink" not in r


@pytest.mark.parametrize("filtro", ["coluna_x eq 1", "filial eq 'a' or", "1 eq 1; DROP TABLE t", "sleep(5) eq 0"])
def test_filtro_invalido_da_400(filtro):
    assert cliente.get("/odata/vw_vendas_item", headers=token(), params={"$filter": filtro}).status_code == 400


def test_injecao_em_texto_vira_valor():
    r = cliente.get("/odata/vw_vendas_item", headers=token(), params={
        "$filter": "filial eq 'x'' OR 1=1 -- '", "$count": "true", "$top": "1"}).json()
    assert r["@odata.count"] == 0
