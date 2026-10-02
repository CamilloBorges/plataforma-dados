from datetime import date

import pytest

from ingestao.f360 import extrator


class Resposta:
    def __init__(self, corpo, status=200):
        self.corpo, self.status_code, self.text = corpo, status, str(corpo)

    def json(self):
        return self.corpo


class SessaoFalsa:
    """Simula a API: `paginas` = lista de páginas (listas de ids) devolvidas para qualquer janela."""

    def __init__(self, paginas, total=None, expira_uma_vez=False):
        self.paginas, self.total, self.expira = paginas, total, expira_uma_vez
        self.gets, self.logins = [], 0

    def post(self, url, json, timeout):
        self.logins += 1
        return Resposta({"Token": f"jwt{self.logins}"})

    def get(self, url, params, timeout, headers):
        if self.expira:
            self.expira = False
            return Resposta({}, 401)
        self.gets.append(params)
        itens = [{"ParcelaId": str(i)} for i in self.paginas[params["pagina"] - 1]]
        total = self.total if self.total is not None else sum(len(p) for p in self.paginas)
        return Resposta({"Ok": True, "Result": {"Parcelas": itens, "QuantidadeDePaginas": len(self.paginas),
                                                 "QuantidadeDeParcelas": total}})


def test_janelas_de_30_dias_cobrem_o_periodo():
    js = list(extrator.janelas(date(2026, 1, 1), date(2026, 3, 1)))
    assert js[0] == (date(2026, 1, 1), date(2026, 1, 30))
    assert js[-1][1] == date(2026, 3, 1)
    assert all((b - a).days < 30 for a, b in js)


def test_parcelas_percorre_paginas_e_janelas():
    s = SessaoFalsa([[1, 2], [3]])
    c = extrator.Cliente("chave", s)
    itens = c.parcelas("Receita", date(2026, 1, 1), date(2026, 2, 15))  # 2 janelas
    assert len(itens) == 6
    assert {g["pagina"] for g in s.gets} == {1, 2}
    assert all(g["tipoDatas"] == "Vencimento" for g in s.gets)


def test_total_divergente_falha():
    s = SessaoFalsa([[1, 2]], total=5)
    with pytest.raises(RuntimeError, match="informa 5"):
        extrator.Cliente("chave", s).parcelas("Despesa", date(2026, 1, 1), date(2026, 1, 10))


def test_renova_jwt_no_401():
    s = SessaoFalsa([[1]], expira_uma_vez=True)
    extrator.Cliente("chave", s).parcelas("Despesa", date(2026, 1, 1), date(2026, 1, 10))
    assert s.logins == 2


def test_erro_nao_vaza_a_chave():
    class Recusa(SessaoFalsa):
        def post(self, url, json, timeout):
            return Resposta("token segredo123 inválido", 400)

    with pytest.raises(RuntimeError) as e:
        extrator.Cliente("segredo123", Recusa([[1]])).get("/x")
    assert "segredo123" not in str(e.value)


def test_linha_normaliza_item():
    item = {
        "ParcelaId": "p1", "Tipo": "Receita", "Vencimento": "2026-09-29", "Liquidacao": "",
        "Status": "Aberto (Vencido)", "ValorBruto": 1722.79, "Numero": "01000226  ", "Conta": "SANTANDER - ARMAZEM",
        "MeioDePagamento": "Boleto", "Cancelada": False,
        "DadosDoTitulo": {"NumeroDoTitulo": "01000226  ",
                          "Empresa": {"Nome": "ARMAZÉM BOMGADO", "Inscricao": "38.824.899/0001-30"},
                          "ClienteFornecedor": {"Nome": "FILHOS DO REINO", "Inscricao": "58.576.805/0001-68"}},
    }
    l = extrator.linha(item)
    assert l["numero"] == "01000226"
    assert l["liquidacao"] is None
    assert l["vencimento"] == "2026-09-29"
    assert l["cliente_fornecedor"] == "FILHOS DO REINO"
