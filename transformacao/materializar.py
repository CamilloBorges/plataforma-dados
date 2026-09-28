"""Materializa as views de transformacao/api/*.sql como TABELAS api.vw_* com chave primária (id).

Tabela e não MATERIALIZED VIEW: a API OData lê o information_schema (que não lista MVs) e exige
chave primária. A troca é atômica: tudo numa transação (DDL é transacional no Postgres), então
quem consulta vê a versão velha até o COMMIT e nunca uma tabela vazia.

Cada .sql começa com "-- atualizar: <agenda>" (usado pela DAG para agendar):
  "uma vez" (legado estático), "15min"/"Nmin", "diario HH:MM".
"""
import re
from pathlib import Path

import psycopg

PASTA = Path(__file__).parent / "api"
NOME = re.compile(r"^vw_[a-z0-9_]+$")


def views() -> dict[str, str]:
    """{nome: agenda} de todas as views da pasta."""
    saida = {}
    for arquivo in sorted(PASTA.glob("vw_*.sql")):
        m = re.search(r"^-- atualizar:\s*(.+)$", arquivo.read_text(encoding="utf-8"), re.M)
        if not m:
            raise ValueError(f"{arquivo.name}: falta a linha '-- atualizar: <agenda>'")
        saida[arquivo.stem] = m.group(1).strip()
    return saida


def sql_da_view(nome: str) -> str:
    if not NOME.match(nome):
        raise ValueError(f"nome de view inválido: {nome}")
    linhas = (PASTA / f"{nome}.sql").read_text(encoding="utf-8").splitlines()
    return "\n".join(l for l in linhas if not l.strip().startswith("--"))


def materializar(db_url: str, nome: str) -> int:
    """Recria api.<nome> a partir do SELECT e devolve o nº de linhas."""
    sql = sql_da_view(nome)
    with psycopg.connect(db_url) as conn:  # uma transação só: a troca é atômica
        conn.execute(f"DROP TABLE IF EXISTS api.{nome}__novo")
        conn.execute(f"CREATE TABLE api.{nome}__novo AS {sql}")
        conn.execute(f"ALTER TABLE api.{nome}__novo ADD PRIMARY KEY (id)")
        conn.execute(f"DROP TABLE IF EXISTS api.{nome}")
        conn.execute(f"ALTER TABLE api.{nome}__novo RENAME TO {nome}")
        conn.execute(f"ALTER INDEX api.{nome}__novo_pkey RENAME TO {nome}_pkey")
        return conn.execute(f"SELECT count(*) FROM api.{nome}").fetchone()[0]
