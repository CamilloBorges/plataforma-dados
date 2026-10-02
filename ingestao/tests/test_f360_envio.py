import pytest

from ingestao.f360 import envio

LINHA = {
    "id": 1, "tipo_titulo": "pagar", "empresa_cnpj": "38.824.899/0001-30", "pessoa_nome": "AGROBRASIL FRIGORIFICO LTDA",
    "pessoa_doc": "44.865.458/0001-89", "numero_titulo": "38336", "tipo_documento": "nota fiscal",
    "emissao": "2026-09-21", "valor": 60666.40,
    "parcelas": [{"numeroParcela": 1, "vencimento": "2026-10-05", "valor": 30333.20, "codigoDeBarras": "123"},
                 {"numeroParcela": 2, "vencimento": "2026-10-19", "valor": 30333.20, "codigoDeBarras": None}],
    "conta_bancaria": "SANTANDER - ARMAZEM", "meio_pagamento": "boleto",
    "plano_de_contas": "Açougue - Compra de Mercadorias (FC)", "centro_de_custo": "Armazém Bomgado ",
    "competencia": "09-2026", "historico": "teste",
}


def test_payload_monta_titulo_com_parcelas_e_rateio():
    t = envio.payload(dict(LINHA))["titulos"][0]
    assert t["clienteFornecedor"] == "44865458000189"
    assert t["detalhesClienteFornecedor"] == {"nome": "AGROBRASIL FRIGORIFICO LTDA", "cpfCnpj": "44865458000189"}
    assert [p["numeroParcela"] for p in t["parcelas"]] == [1, 2]
    assert t["parcelas"][0]["liquidacao"] is None and t["parcelas"][0]["codigoDeBarras"] == "123"
    assert [r["valor"] for r in t["rateio"]] == [30333.20, 30333.20]
    assert all(r["planoDeContas"].startswith("Açougue") and r["competencia"] == "09-2026" for r in t["rateio"])


def test_payload_recusa_soma_que_nao_fecha():
    linha = dict(LINHA, valor=60000)
    with pytest.raises(ValueError, match="não fecha"):
        envio.payload(linha)


def test_payload_exige_plano_e_listas_do_f360():
    with pytest.raises(ValueError, match="plano_de_contas"):
        envio.payload(dict(LINHA, plano_de_contas=None))
    with pytest.raises(ValueError, match="meio de pagamento"):
        envio.payload(dict(LINHA, meio_pagamento="pix"))


def test_payload_sem_documento_usa_o_nome():
    t = envio.payload(dict(LINHA, pessoa_doc=None))["titulos"][0]
    assert t["clienteFornecedor"] == "AGROBRASIL FRIGORIFICO LTDA" and "detalhesClienteFornecedor" not in t


class Cursor:
    def __init__(self, linhas=None, colunas=None):
        self._linhas = linhas or []
        self.description = [type("C", (), {"name": c}) for c in (colunas or [])]
        self.rowcount = len(self._linhas)

    def fetchall(self):
        return self._linhas

    def fetchone(self):
        return self._linhas[0] if self._linhas else None


class Conexao:
    """Simula o banco: a fila tem as linhas dadas; `no_f360` = números já presentes em raw_f360."""

    def __init__(self, linhas, no_f360=()):
        self.linhas, self.no_f360, self.updates = linhas, set(no_f360), []

    def execute(self, sql, params=None):
        if sql.startswith("SELECT * FROM config.f360_envio"):
            colunas = list(self.linhas[0]) if self.linhas else []
            return Cursor([tuple(l.values()) for l in self.linhas], colunas)
        if "FROM raw_f360.parcela_titulo" in sql:
            return Cursor([(1,)] if params["numero"] in self.no_f360 else [])
        self.updates.append((sql.split("SET ")[1].split(",")[0], params))
        return Cursor()


class Resposta:
    def __init__(self, status, corpo):
        self.status_code, self._corpo, self.text = status, corpo, str(corpo)

    def json(self):
        return self._corpo


def test_enviar_manda_aprovado_e_guarda_rastreio():
    conn = Conexao([dict(LINHA, status="aprovado")])
    enviados = []
    r = envio.enviar(conn, "https://webhook", post=lambda url, json, timeout: (enviados.append(json), Resposta(200, {"rastreioId": "abc"}))[1])
    assert r == {"enviados": 1, "ja_existiam": 0, "erros": 0}
    assert enviados[0]["titulos"][0]["numeroTitulo"] == "38336"
    assert conn.updates[0][0].startswith("status = 'enviado'") and conn.updates[0][1] == ("abc", 1)


def test_enviar_nao_duplica_o_que_ja_esta_no_f360():
    conn = Conexao([dict(LINHA, status="aprovado")], no_f360={"38336"})
    r = envio.enviar(conn, "https://webhook", post=lambda *a, **k: pytest.fail("não devia enviar"))
    assert r["ja_existiam"] == 1 and conn.updates[0][0].startswith("status = 'confirmado'")


def test_enviar_registra_erro_e_segue():
    conn = Conexao([dict(LINHA, status="aprovado", plano_de_contas=None)])
    r = envio.enviar(conn, "https://webhook", post=lambda *a, **k: pytest.fail("não devia enviar"))
    assert r["erros"] == 1 and conn.updates[0][0].startswith("status = 'erro'")
