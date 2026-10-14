"""Troca da tabela de cópia pela versão nova (<tabela>__novo), dentro da transação de quem chama.

Tabela com as mesmas colunas: TRUNCATE + INSERT da nova, mantendo a tabela. As views que dependem
dela (staging do dbt em stg) continuam valendo. Um DROP + RENAME seria recusado pelo Postgres
("cannot drop table ... because other objects depend on it"), e a cópia ficaria parada.
Colunas diferentes (a origem mudou): DROP ... CASCADE + RENAME, que derruba as views dependentes;
o próximo dbt build as recria com as colunas novas (fica um aviso no log).
"""
import logging

import psycopg
from psycopg import sql

log = logging.getLogger(__name__)

_COLUNAS = """
SELECT a.attname, format_type(a.atttypid, a.atttypmod)
FROM pg_attribute a
WHERE a.attrelid = to_regclass(%s) AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum
"""


def colunas(pg: psycopg.Connection, schema: str, tabela: str) -> list[tuple[str, str]]:
    """[(nome, tipo)] da tabela, ou [] se ela não existe."""
    nome = sql.Identifier(schema, tabela).as_string(pg)
    return [tuple(c) for c in pg.execute(_COLUNAS, [nome]).fetchall()]


def trocar(pg: psycopg.Connection, schema: str, tabela: str, pk: list[str] | None = None) -> None:
    """Põe <schema>.<tabela>__novo no lugar de <schema>.<tabela> (chamar dentro de uma transação)."""
    novo = f"{tabela}__novo"
    alvo = sql.Identifier(schema, tabela)
    tmp = sql.Identifier(schema, novo)
    atuais = colunas(pg, schema, tabela)
    if atuais and atuais == colunas(pg, schema, novo):
        pg.execute(sql.SQL("TRUNCATE {}").format(alvo))
        pg.execute(sql.SQL("INSERT INTO {} SELECT * FROM {}").format(alvo, tmp))
        pg.execute(sql.SQL("DROP TABLE {}").format(tmp))
        return
    if atuais:
        log.warning("%s.%s mudou de colunas: tabela recriada (DROP CASCADE); as views dependentes "
                    "voltam no próximo dbt build", schema, tabela)
    pg.execute(sql.SQL("DROP TABLE IF EXISTS {} CASCADE").format(alvo))
    pg.execute(sql.SQL("ALTER TABLE {} RENAME TO {}").format(tmp, sql.Identifier(tabela)))
    if pk:
        pg.execute(sql.SQL("ALTER TABLE {} ADD CONSTRAINT {} PRIMARY KEY ({})").format(
            alvo, sql.Identifier(f"{tabela}_pkey"), sql.SQL(", ").join(map(sql.Identifier, pk))))
