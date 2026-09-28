import pytest

from ingestao.jetbov import extrator


class Resposta:
    def __init__(self, corpo):
        self.corpo = corpo

    def raise_for_status(self):
        pass

    def json(self):
        return self.corpo


class SessaoFalsa:
    """Simula a API: 3 páginas de eventos confirmados e 1 de não confirmados."""

    def __init__(self):
        self.headers = {}
        self.chamadas = []

    def post(self, url, json, timeout):
        return Resposta({"Token": "abc"})

    def get(self, url, params, timeout):
        self.chamadas.append(params)
        total = 3 if params["confirmed"] == "True" else 1
        return Resposta({"health_events": [{"id": params["page"]}], "meta": {"total_pages": total}})


def test_login_poe_token_no_cabecalho():
    s = SessaoFalsa()
    extrator.login(s, "u", "p")
    assert s.headers["Authorization"] == "Token abc"


def test_login_sem_token_falha():
    s = SessaoFalsa()
    s.post = lambda url, json, timeout: Resposta({"non_field_errors": ["x"]})
    with pytest.raises(RuntimeError):
        extrator.login(s, "u", "p")


def test_paginas_percorre_todas_confirmadas_e_nao_confirmadas():
    s = SessaoFalsa()
    resultado = list(extrator.paginas(s, "healthEvents/", "health_events"))
    assert [(p["confirmed"], p["page"]) for p, _ in resultado] == [
        ("True", 1), ("True", 2), ("True", 3), ("False", 1),
    ]


def test_paginas_falha_se_chave_mudar():
    s = SessaoFalsa()
    with pytest.raises(RuntimeError):
        list(extrator.paginas(s, "healthEvents/", "outra_chave"))
