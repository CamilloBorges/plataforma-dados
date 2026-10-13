"""Leitura de tabelas Delta do lakehouse do Fabric (OneLake) para o schema raw_fabric. SOMENTE LEITURA.

Ponte da migração da Rentabilidade por Setor (nota "Plataforma de Dados Bomgado"): enquanto o Fabric
calcula o custo médio do açougue (notebook "Calculo custo Açougue"), a plataforma importa o
resultado; as gold do Fato Item vêm para a conferência no centavo. Sai quando o Fabric for desligado.

O OneLake só responde com a capacidade do Fabric ligada (ela roda os extratores de 09:00 a 21:15).
Login: app do Entra no locatário do Fabric, com leitura no lakehouse (FABRIC_TENANT_ID,
FABRIC_CLIENT_ID, FABRIC_CLIENT_SECRET, do cofre). Cópia completa com troca atômica, como no Logus.
"""
import logging
import re
import time
from pathlib import Path

import psycopg
from psycopg import sql

CONF = Path(__file__).with_name("tabelas.conf")
CAMINHO = re.compile(r"^[a-z0-9_]+/[a-z0-9_]+$")  # <schema do lakehouse>/<tabela>
NOME = re.compile(r"^[a-z0-9_]+$")

log = logging.getLogger(__name__)

DDL = """
CREATE TABLE IF NOT EXISTS raw_fabric.carga (
    id bigserial PRIMARY KEY,
    tabela text NOT NULL,
    origem text NOT NULL,
    versao_delta bigint,
    inicio timestamptz NOT NULL DEFAULT now(),
    fim timestamptz,
    linhas bigint,
    erro text
);
"""


def tabelas(conf: Path = CONF) -> dict[str, str]:
    """{tabela de destino: caminho no lakehouse} do tabelas.conf, validando os nomes."""
    saida = {}
    for linha in conf.read_text(encoding="utf-8").splitlines():
        linha = re.sub(r"#.*", "", linha).strip()
        if not linha:
            continue
        origem, _, destino = linha.partition(" ")
        destino = destino.strip()
        if not CAMINHO.match(origem) or not NOME.match(destino):
            raise ValueError(f"linha inválida no tabelas.conf: {linha!r}")
        saida[destino] = origem
    return saida


def tipo_pg(tipo) -> str:
    """Tipo do Postgres para um tipo do Arrow (o que o Delta do Fabric usa)."""
    import pyarrow as pa

    if pa.types.is_boolean(tipo):
        return "boolean"
    if pa.types.is_integer(tipo):
        return "bigint"
    if pa.types.is_floating(tipo):
        return "double precision"
    if pa.types.is_decimal(tipo):
        return f"numeric({tipo.precision},{tipo.scale})"
    if pa.types.is_date(tipo):
        return "date"
    if pa.types.is_timestamp(tipo):
        return "timestamptz" if tipo.tz else "timestamp"
    return "text"


def copiar(pg: psycopg.Connection, destino: str, tabela) -> int:
    """Grava a tabela Arrow em raw_fabric.<destino> com troca atômica; devolve o nº de linhas."""
    cols = [(c.lower(), tipo_pg(t)) for c, t in zip(tabela.schema.names, tabela.schema.types)]
    alvo = sql.Identifier("raw_fabric", destino)
    tmp = sql.Identifier("raw_fabric", f"{destino}__novo")
    ddl = sql.SQL(", ").join(sql.SQL("{} {}").format(sql.Identifier(n), sql.SQL(t)) for n, t in cols)
    with pg.transaction():
        pg.execute(sql.SQL("DROP TABLE IF EXISTS {}").format(tmp))
        pg.execute(sql.SQL("CREATE TABLE {} ({})").format(tmp, ddl))
        with pg.cursor().copy(sql.SQL("COPY {} FROM STDIN").format(tmp)) as copia:
            for lote in tabela.to_batches():
                for linha in zip(*(lote.column(i).to_pylist() for i in range(lote.num_columns))):
                    copia.write_row(linha)
        pg.execute(sql.SQL("DROP TABLE IF EXISTS {}").format(alvo))
        pg.execute(sql.SQL("ALTER TABLE {} RENAME TO {}").format(tmp, sql.Identifier(destino)))
    return tabela.num_rows


def opcoes(tenant: str, cliente: str, segredo: str) -> dict:
    return {
        "azure_tenant_id": tenant,
        "azure_client_id": cliente,
        "azure_client_secret": segredo,
        "use_fabric_endpoint": "true",
    }


def executar(db_url: str, workspace: str, lakehouse: str, tenant: str, cliente: str, segredo: str) -> dict:
    """Copia todas as tabelas do tabelas.conf. Falha de uma não impede as demais, mas no fim
    levanta erro (a tarefa fica vermelha)."""
    from deltalake import DeltaTable

    resultado, erros = {}, {}
    with psycopg.connect(db_url, autocommit=True) as pg:
        pg.execute(DDL)
        for destino, origem in tabelas().items():
            carga = pg.execute("INSERT INTO raw_fabric.carga (tabela, origem) VALUES (%s, %s) RETURNING id",
                               [destino, origem]).fetchone()[0]
            inicio = time.monotonic()
            try:
                caminho = f"abfss://{workspace}@onelake.dfs.fabric.microsoft.com/{lakehouse}/Tables/{origem}"
                dt = DeltaTable(caminho, storage_options=opcoes(tenant, cliente, segredo))
                linhas = copiar(pg, destino, dt.to_pyarrow_table())
                pg.execute("UPDATE raw_fabric.carga SET fim = now(), linhas = %s, versao_delta = %s WHERE id = %s",
                           [linhas, dt.version(), carga])
                resultado[destino] = linhas
                log.info("Fabric: %s, %s linhas em %.0f s", destino, linhas, time.monotonic() - inicio)
            except Exception as e:  # noqa: BLE001 - registra e segue para a próxima tabela
                pg.execute("UPDATE raw_fabric.carga SET fim = now(), erro = %s WHERE id = %s", [str(e)[:2000], carga])
                erros[destino] = str(e)
                log.error("Fabric: erro em %s: %s", destino, e)
    if erros:
        raise RuntimeError(f"falha em {len(erros)} tabela(s): {erros}")
    return resultado
