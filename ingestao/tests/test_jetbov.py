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
    """Simula a API paginada. `paginas_por_filtro` = {confirmed: [[ids da pág. 1], [ids da pág. 2], ...]}."""

    def __init__(self, paginas_por_filtro):
        self.headers = {}
        self.chamadas = []
        self.paginas_por_filtro = paginas_por_filtro

    def post(self, url, json, timeout):
        return Resposta({"Token": "abc"})

    def get(self, url, params, timeout):
        self.chamadas.append(params)
        paginas = self.paginas_por_filtro[params.get("confirmed")]
        total = sum(len(p) for p in paginas)
        itens = [{"id": i} for i in paginas[params["page"] - 1]]
        return Resposta({"health_events": itens, "meta": {"total_pages": len(paginas), "total_results": total}})


def test_login_poe_token_no_cabecalho():
    s = SessaoFalsa({})
    extrator.login(s, "u", "p")
    assert s.headers["Authorization"] == "Token abc"


def test_login_sem_token_falha():
    s = SessaoFalsa({})
    s.post = lambda url, json, timeout: Resposta({"non_field_errors": ["x"]})
    with pytest.raises(RuntimeError):
        extrator.login(s, "u", "p")


def test_paginas_com_filtro_percorre_confirmados_e_nao_confirmados():
    s = SessaoFalsa({"True": [[1, 2], [3]], "False": [[4]]})
    resultado = list(extrator.paginas(s, "healthEvents/", "health_events", True))
    assert [(p["confirmed"], p["page"]) for p, _ in resultado] == [("True", 1), ("True", 2), ("False", 1)]


def test_paginas_sem_filtro_nao_manda_confirmed():
    s = SessaoFalsa({None: [[1, 2, 3]]})
    list(extrator.paginas(s, "nutritionEvents/", "health_events", False))
    assert s.chamadas == [{"page": 1, "per_page": extrator.POR_PAGINA}]


def test_paginas_falha_se_ids_nao_baterem_com_o_total():
    # Página 2 repete o id 2 (paginação instável): 3 IDs distintos, mas a API informa 4.
    s = SessaoFalsa({None: [[1, 2], [2, 3]]})
    with pytest.raises(RuntimeError, match="IDs distintos"):
        list(extrator.paginas(s, "nutritionEvents/", "health_events", False))


def test_paginas_falha_se_chave_mudar():
    s = SessaoFalsa({None: [[1]]})
    with pytest.raises(RuntimeError, match="resposta sem"):
        list(extrator.paginas(s, "nutritionEvents/", "outra_chave", False))
