import os
from datetime import date

import pyarrow as pa
import pytest

from ingestao.fabric import extrator


def test_tabelas_conf_real():
    t = extrator.tabelas()
    assert t["custo_medio_acougue"] == "dbo/gold_custo_medio_acougue"


def test_tabelas_recusa_linha_invalida(tmp_path):
    conf = tmp_path / "t.conf"
    conf.write_text("dbo/Gold_Custo  custo\n", encoding="utf-8")  # maiúscula: o OneLake usa minúsculas
    with pytest.raises(ValueError):
        extrator.tabelas(conf)
    conf.write_text("dbo/x; drop  x\n", encoding="utf-8")
    with pytest.raises(ValueError):
        extrator.tabelas(conf)


@pytest.mark.parametrize("tipo, esperado", [
    (pa.int64(), "bigint"), (pa.int32(), "bigint"), (pa.float64(), "double precision"),
    (pa.decimal128(36, 8), "numeric(36,8)"), (pa.date32(), "date"), (pa.bool_(), "boolean"),
    (pa.timestamp("us", tz="UTC"), "timestamptz"), (pa.timestamp("us"), "timestamp"), (pa.string(), "text"),
])
def test_tipo_pg(tipo, esperado):
    assert extrator.tipo_pg(tipo) == esperado


@pytest.mark.skipif(not os.environ.get("TEST_DB_URL"), reason="defina TEST_DB_URL (Postgres descartável)")
def test_copiar_troca_atomica():
    import psycopg

    tabela = pa.table({"Ano": [2026, 2026], "Mes": [9, 10], "eanBalanca": [31, 1373],
                       "vlrUnitario": [36.95, None], "ultimoCusto": [date(2026, 9, 1), date(2026, 10, 1)]})
    with psycopg.connect(os.environ["TEST_DB_URL"], autocommit=True) as pg:
        pg.execute("CREATE SCHEMA IF NOT EXISTS raw_fabric")
        assert extrator.copiar(pg, "teste_custo", tabela) == 2
        assert extrator.copiar(pg, "teste_custo", tabela.slice(0, 1)) == 1
        linhas = pg.execute("SELECT ano, mes, eanbalanca, vlrunitario, ultimocusto FROM raw_fabric.teste_custo").fetchall()
        assert linhas == [(2026, 9, 31, 36.95, date(2026, 9, 1))]
        pg.execute("DROP TABLE raw_fabric.teste_custo")
