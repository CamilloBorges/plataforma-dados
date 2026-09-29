import os
from decimal import Decimal

import pytest

from ingestao.logus import extrator


class Valor:
    """Imita um objeto Java (java.sql.Date, BigDecimal...): str() = toString()."""

    def __init__(self, texto):
        self.texto = texto

    def __str__(self):
        return self.texto


class ResultSetFalso:
    """Imita o java.sql.ResultSet (índices a partir de 1)."""

    def __init__(self, linhas):
        self.linhas, self.pos, self.nulo = linhas, -1, False

    def next(self):
        self.pos += 1
        return self.pos < len(self.linhas)

    def _v(self, i):
        v = self.linhas[self.pos][i - 1]
        self.nulo = v is None
        return v

    def getString(self, i):
        return self._v(i)

    getBigDecimal = getDate = getTime = getTimestamp = getBytes = getString

    def getBoolean(self, i):
        v = self._v(i)
        return bool(v) if v is not None else False

    def wasNull(self):
        return self.nulo


def test_tabelas_conf_real():
    t = extrator.tabelas()
    assert t["vnditenspdv"] == "15min"
    assert t["cadprod"] == "diario 03:00"


def test_tabelas_recusa_nome_e_agenda_invalidos(tmp_path):
    conf = tmp_path / "t.conf"
    conf.write_text("vndpdv; drop  15min\n", encoding="utf-8")
    with pytest.raises(ValueError):
        extrator.tabelas(conf)
    conf.write_text("vndpdv  toda hora\n", encoding="utf-8")
    with pytest.raises(ValueError):
        extrator.tabelas(conf)


@pytest.mark.parametrize("tipo,p,s,esperado", [
    (3, 16, 2, "numeric(16,2)"),
    (3, 16, 255, "numeric"),  # DECIMAL(p) flutuante do Informix
    (4, 10, 0, "integer"),
    (1, 30, 0, "text"),
    (93, 23, 3, "timestamp"),
    (91, 10, 0, "date"),
    (16, 1, 0, "boolean"),
    (1111, 0, 0, "text"),  # tipo desconhecido
])
def test_tipo_pg(tipo, p, s, esperado):
    assert extrator.tipo_pg(tipo, p, s) == esperado


def test_leitores():
    rs = ResultSetFalso([
        ["ABC   ", Valor("12.50"), Valor("2026-09-29"), 1, "42", None],
        [None, None, None, None, None, "x\x00y  "],
    ])
    tipos = ["text", "numeric(10,2)", "date", "boolean", "integer", "text"]
    leitores = [extrator.leitor(t) for t in tipos]
    rs.next()
    assert [f(rs, i) for i, f in enumerate(leitores, 1)] == ["ABC", "12.50", "2026-09-29", "t", "42", None]
    rs.next()
    assert [f(rs, i) for i, f in enumerate(leitores, 1)] == [None, None, None, None, None, "xy"]


@pytest.mark.skipif(not os.environ.get("TEST_DB_URL"), reason="defina TEST_DB_URL (Postgres descartável)")
def test_copiar_troca_atomica():
    import psycopg

    cols = [("id", "integer"), ("nome", "text"), ("valor", "numeric(10,2)"), ("dia", "date")]
    with psycopg.connect(os.environ["TEST_DB_URL"], autocommit=True) as pg:
        pg.execute("CREATE SCHEMA IF NOT EXISTS raw_logus")
        pg.execute("DROP TABLE IF EXISTS raw_logus.teste")
        for rodada in (1, 2):  # a 2ª rodada troca a tabela existente
            rs = ResultSetFalso([[str(i), f"item {i}  ", Valor("1.5"), Valor("2026-09-29")] for i in range(rodada * 3)])
            assert extrator.copiar(pg, "teste", cols, ["id"], rs) == rodada * 3
        assert pg.execute("SELECT count(*), sum(valor), min(nome) FROM raw_logus.teste").fetchone() == (6, Decimal("9.00"), "item 0")
        pk = pg.execute("SELECT conname FROM pg_constraint WHERE conrelid = 'raw_logus.teste'::regclass AND contype = 'p'").fetchone()
        assert pk == ("teste_pkey",)
        assert pg.execute("SELECT to_regclass('raw_logus.teste__novo')").fetchone() == (None,)
        pg.execute("DROP TABLE raw_logus.teste")
