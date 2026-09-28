"""Gateway OData v4 somente leitura sobre as tabelas api.vw_* do Postgres (banco "dados"), com login do Entra ID.

Pensado para o Excel/Power BI ("Obter Dados → De Feed OData", "Conta organizacional"):
  GET /odata/            lista as views (o Navegador do Excel)
  GET /odata/$metadata   tipos das colunas (lidos do information_schema)
  GET /odata/<view>      dados, com $select $filter $orderby $top $skip $count e paginação
Sem token: 401 com WWW-Authenticate apontando para o Entra ID (é o que faz o Excel pedir login).
Com token: valida assinatura, tenant, audiência (= domínio da API) e, se ENTRA_GROUP_ID, o grupo.
"""
import os
import re
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from urllib.parse import urlencode
from xml.sax.saxutils import escape

import jwt
import psycopg
from psycopg.rows import dict_row
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response

from odata_filter import FiltroInvalido, traduzir

TENANT = os.environ.get("ENTRA_TENANT_ID", "").strip()
AUDIENCIAS = [a.strip() for a in os.environ.get("ENTRA_AUDIENCE", "").split(",") if a.strip()]  # URI da API e/ou client id
if not TENANT or not AUDIENCIAS or not os.environ.get("API_DB_PASSWORD"):
    raise SystemExit("defina ENTRA_TENANT_ID, ENTRA_AUDIENCE e API_DB_PASSWORD")
GRUPO = os.environ.get("ENTRA_GROUP_ID", "").strip()
PAGINA = int(os.environ.get("PAGE_SIZE", "20000"))
EMISSORES = [f"https://sts.windows.net/{TENANT}/", f"https://login.microsoftonline.com/{TENANT}/v2.0"]
jwks = jwt.PyJWKClient(f"https://login.microsoftonline.com/{TENANT}/discovery/v2.0/keys", cache_keys=True)

NS = "Pleno"
VIEW = re.compile(r"^vw_[a-z0-9_]+$")
EDM = {"integer": "Edm.Int32", "smallint": "Edm.Int16", "bigint": "Edm.Int64", "numeric": "Edm.Decimal",
       "double precision": "Edm.Double", "real": "Edm.Double", "boolean": "Edm.Boolean", "date": "Edm.Date",
       "timestamp without time zone": "Edm.DateTimeOffset", "timestamp with time zone": "Edm.DateTimeOffset",
       "time without time zone": "Edm.TimeOfDay"}

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def conectar():
    return psycopg.connect(host=os.environ.get("DB_HOST", "postgres"), user="api_leitura",
                           password=os.environ["API_DB_PASSWORD"], dbname="dados",
                           row_factory=dict_row, autocommit=True)


def esquema():
    """{view: [(coluna, tipo, precisão, escala)]} — só api.vw_* com chave primária."""
    with conectar() as c, c.cursor() as cur:
        cur.execute(r"""SELECT c.table_name t, c.column_name col, c.data_type tipo,
                               c.numeric_precision p, c.numeric_scale s
                        FROM information_schema.columns c
                        JOIN information_schema.table_constraints k
                          ON k.table_schema = c.table_schema AND k.table_name = c.table_name
                         AND k.constraint_type = 'PRIMARY KEY'
                        WHERE c.table_schema = 'api' AND c.table_name LIKE 'vw\_%'
                          AND c.table_name NOT LIKE '%\_\_novo'
                        ORDER BY c.table_name, c.ordinal_position""")
        saida = {}
        for r in cur.fetchall():
            saida.setdefault(r["t"], []).append((r["col"], r["tipo"], r["p"], r["s"]))
        return saida


def autenticar(request: Request):
    auth = request.headers.get("authorization", "")
    token = auth[7:].strip() if auth.lower().startswith("bearer ") else ""
    desafio = {"WWW-Authenticate": f'Bearer authorization_uri="https://login.microsoftonline.com/{TENANT}/oauth2/authorize"'}
    if not token:
        raise HTTPException(401, "login necessário", headers=desafio)
    try:
        chave = jwks.get_signing_key_from_jwt(token).key
        claims = jwt.decode(token, chave, algorithms=["RS256"], audience=AUDIENCIAS, issuer=EMISSORES)
    except Exception as e:
        raise HTTPException(401, f"token inválido: {e}", headers=desafio)
    if GRUPO and GRUPO not in claims.get("groups", []):
        raise HTTPException(403, "usuário fora do grupo autorizado")
    return claims


def odata(corpo, status=200):
    return JSONResponse(corpo, status_code=status, headers={"OData-Version": "4.0"})


def base(request: Request):
    return str(request.base_url).rstrip("/") + "/odata"


@app.get("/odata")
@app.get("/odata/")
def servico(request: Request):
    autenticar(request)
    b = base(request)
    return odata({"@odata.context": f"{b}/$metadata",
                  "value": [{"name": v, "kind": "EntitySet", "url": v} for v in esquema()]})


@app.get("/odata/$metadata")
def metadata(request: Request):
    autenticar(request)
    tipos, conjuntos = [], []
    for v, cols in esquema().items():
        props = []
        for col, tipo, p, s in cols:
            edm = EDM.get(tipo, "Edm.String")
            extra = f' Precision="{p}" Scale="{s}"' if edm == "Edm.Decimal" and p else ""
            nulo = ' Nullable="false"' if col == "id" else ""
            props.append(f'<Property Name="{escape(col)}" Type="{edm}"{extra}{nulo}/>')
        tipos.append(f'<EntityType Name="{v}"><Key><PropertyRef Name="id"/></Key>{"".join(props)}</EntityType>')
        conjuntos.append(f'<EntitySet Name="{v}" EntityType="{NS}.{v}"/>')
    xml = ('<?xml version="1.0" encoding="utf-8"?>'
           '<edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">'
           f'<edmx:DataServices><Schema Namespace="{NS}" xmlns="http://docs.oasis-open.org/odata/ns/edm">'
           f'{"".join(tipos)}<EntityContainer Name="Container">{"".join(conjuntos)}</EntityContainer>'
           '</Schema></edmx:DataServices></edmx:Edmx>')
    return Response(xml, media_type="application/xml", headers={"OData-Version": "4.0"})


def valor_json(v):
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, datetime):  # datas-hora do legado são horário local; vão com "Z" e voltam iguais
        return v.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, timedelta):  # intervalo
        s = int(v.total_seconds())
        return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}"
    if isinstance(v, time):
        return v.strftime("%H:%M:%S")
    if isinstance(v, (bytes, bytearray)):
        return v.hex()
    return v


@app.get("/odata/{view}")
def dados(view: str, request: Request):
    autenticar(request)
    q = request.query_params
    views = esquema()
    if not VIEW.match(view) or view not in views:
        return odata({"error": {"code": "404", "message": f"view inexistente: {view}"}}, 404)
    colunas = [c[0] for c in views[view]]

    select = colunas
    if q.get("$select"):
        select = [s.strip() for s in q["$select"].split(",")]
        if any(s not in colunas for s in select):
            return odata({"error": {"code": "400", "message": "coluna inexistente no $select"}}, 400)
        if "id" not in select:
            select = ["id"] + select  # a paginação usa o id

    where, params = [], []
    if q.get("$filter"):
        try:
            sql, p = traduzir(q["$filter"], colunas)
        except FiltroInvalido as e:
            return odata({"error": {"code": "400", "message": str(e)}}, 400)
        where.append(sql)
        params += p

    ordem = []
    if q.get("$orderby"):
        for parte in q["$orderby"].split(","):
            nome, *direcao = parte.strip().split()
            if nome not in colunas or (direcao and direcao[0].lower() not in ("asc", "desc")):
                return odata({"error": {"code": "400", "message": f"$orderby inválido: {parte}"}}, 400)
            ordem.append(f'"{nome}" {direcao[0].upper() if direcao else "ASC"}')

    top = int(q["$top"]) if q.get("$top") else None
    skip = int(q.get("$skip", 0))
    limite = PAGINA if top is None else min(top, PAGINA)
    filtro_sql = " AND ".join(where)  # só o $filter: é o que o $count usa
    filtro_params = list(params)

    # Sem $orderby, pagina por chave (id > último): rápido mesmo com milhões de linhas.
    # Com $orderby (ou $skip na primeira página), usa OFFSET.
    apos = q.get("$skiptoken")
    usa_offset = bool(ordem) or (skip > 0 and apos is None)
    if not ordem and apos is not None:
        where.append('"id" > %s')
        params.append(int(apos))
    colunas_sql = ", ".join(f'"{c}"' for c in select)
    ordem_sql = ", ".join(ordem) if ordem else '"id"'
    sql = (f'SELECT {colunas_sql} FROM api."{view}"'
           + (f" WHERE {' AND '.join(where)}" if where else "")
           + f" ORDER BY {ordem_sql} LIMIT %s"
           + (" OFFSET %s" if usa_offset else ""))
    params += [limite, skip] if usa_offset else [limite]

    with conectar() as c, c.cursor() as cur:
        cur.execute(sql, params)
        linhas = [{k: valor_json(v) for k, v in r.items()} for r in cur.fetchall()]
        total = None
        if q.get("$count", "").lower() == "true":
            cur.execute(f'SELECT count(*) n FROM api."{view}"' + (f" WHERE {filtro_sql}" if filtro_sql else ""), filtro_params)
            total = cur.fetchone()["n"]

    corpo = {"@odata.context": f"{base(request)}/$metadata#{view}"}
    if total is not None:
        corpo["@odata.count"] = total
    corpo["value"] = linhas
    # Próxima página: só quando o cliente não pediu um $top menor que a página.
    restante = None if top is None else top - len(linhas)
    if len(linhas) == limite and (restante is None or restante > 0):
        prox = dict(q)
        if ordem:
            prox["$skip"] = str(skip + len(linhas))
        else:
            prox["$skiptoken"] = str(linhas[-1]["id"])
            prox.pop("$skip", None)
        if restante is not None:
            prox["$top"] = str(restante)
        corpo["@odata.nextLink"] = f"{base(request)}/{view}?{urlencode(prox)}"
    return odata(corpo)


@app.get("/health")
def saude():
    return {"ok": True}
