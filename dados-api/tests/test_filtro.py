"""Testes unitários do tradutor $filter → SQL do Postgres (não precisam de banco)."""
from datetime import date

import pytest

from odata_filter import FiltroInvalido, traduzir

COLS = ["data", "filial", "mercadoria", "valor_total", "classificacao"]


def test_comparacao_e_texto_com_aspas_duplas():
    sql, p = traduzir("filial eq 'BOM KAFE' and valor_total gt 10", COLS)
    assert sql == '(("filial" = %s) AND ("valor_total" > %s))'
    assert p == ["BOM KAFE", 10]


def test_contains_ignora_maiusculas():
    sql, p = traduzir("contains(mercadoria,'cafe')", COLS)
    assert sql == "(\"mercadoria\" ILIKE CONCAT('%%', %s, '%%'))"
    assert p == ["cafe"]


def test_funcoes_de_data_no_postgres():
    sql, p = traduzir("year(data) eq 2025 and date(data) ge 2025-12-01", COLS)
    assert sql == '((EXTRACT(YEAR FROM "data") = %s) AND (CAST("data" AS date) >= %s))'
    assert p == [2025, date(2025, 12, 1)]


def test_null_e_booleano():
    assert traduzir("classificacao ne null", COLS)[0] == '("classificacao" IS NOT NULL)'
    assert traduzir("valor_total eq true", COLS)[0] == '("valor_total" = TRUE)'


@pytest.mark.parametrize("filtro", ["coluna_x eq 1", "filial eq 'a' or", "1 eq 1; DROP TABLE t"])
def test_filtro_invalido(filtro):
    with pytest.raises(FiltroInvalido):
        traduzir(filtro, COLS)
