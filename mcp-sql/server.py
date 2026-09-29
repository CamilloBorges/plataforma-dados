"""MCP somente leitura para consultar o Postgres da plataforma de dados (substitui o Directus/MCP pleno).

Segurança em camadas: usuário mcp_leitura só tem SELECT (api, legado, raw_*); o papel já nasce com
default_transaction_read_only e statement_timeout de 60 s (infra/postgres/setup.sh); e toda consulta
vai embrulhada num SELECT externo, o que impede mandar vários comandos de uma vez. Na borda, o acesso
é protegido pelo token de serviço do Cloudflare Access (como os demais MCPs).
"""
import os
import re
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Any
from uuid import UUID

import psycopg
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from mcp.types import ToolAnnotations

INSTRUCOES = """Consulta somente leitura ao banco da plataforma de dados Bomgado (Postgres).
Schemas:
- api: tabelas prontas vw_* (as mesmas do Excel/OData), comece por aqui.
- legado: cópia do ERP antigo PlenoKW (564 tabelas, até 26/07/2026). Prefixos: fcx frente de caixa,
  est estoque/produção, fis fiscal, mcd mercadorias, fin/tes financeiro, cfg02 classificação mercadológica.
- raw_jetbov: respostas brutas da API do JetBov (fazenda), em jsonb, por execução (raw_jetbov.resposta).
- raw_logus: cópia do ERP atual (Informix/Logus).
- config: de/para mantidos no Directus (ex.: depara_produto). As tabelas directus_* não são legíveis.
Use listar_tabelas e descrever_tabela antes de consultar. Consultas só com SELECT/WITH; o limite de
linhas é aplicado automaticamente (avisa com truncado=true)."""

_hosts = [h.strip() for h in os.getenv("MCP_TRUSTED_HOSTS", "").split(",") if h.strip()]
_seguranca = (
    TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=_hosts,
        allowed_origins=[f"https://{h}" for h in _hosts],
    )
    if _hosts
    else None
)
mcp = FastMCP("dados", instructions=INSTRUCOES, transport_security=_seguranca)
LEITURA = ToolAnnotations(readOnlyHint=True, openWorldHint=False)
SCHEMAS = ("api", "legado", "raw_jetbov", "raw_logus", "config")
LIMITE_MAX = 2000


def _conectar():
    return psycopg.connect(
        host=os.getenv("DB_HOST", "postgres"), dbname="dados", user="mcp_leitura",
        password=os.environ["MCP_DB_PASSWORD"], autocommit=False,
    )


def _json(v: Any) -> Any:
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (datetime, date, time)):
        return v.isoformat()
    if isinstance(v, timedelta):
        return str(v)
    if isinstance(v, (UUID, bytes, memoryview)):
        return str(v) if isinstance(v, UUID) else bytes(v).hex()
    return v


def _consultar(sql: str, params: tuple = ()) -> tuple[list[str], list[list]]:
    with _conectar() as conn, conn.cursor() as cur:
        conn.read_only = True
        cur.execute(sql, params)
        colunas = [d.name for d in cur.description]
        return colunas, [[_json(v) for v in linha] for linha in cur.fetchall()]


@mcp.tool(annotations=LEITURA)
def listar_tabelas(schema: str, filtro: str = "") -> list[dict]:
    """Tabelas de um schema (api, legado, raw_jetbov, raw_logus), com nº aproximado de linhas.
    `filtro` opcional: trecho do nome (ex.: 'fcx', 'estoque')."""
    if schema not in SCHEMAS:
        raise ValueError(f"schema deve ser um de {SCHEMAS}")
    _, linhas = _consultar(
        """SELECT c.relname, greatest(c.reltuples, 0)::bigint, obj_description(c.oid)
           FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = %s AND c.relkind IN ('r', 'v', 'm') AND c.relname ILIKE %s
             AND c.relname NOT LIKE '%%\\_\\_novo'
           ORDER BY c.relname""",
        (schema, f"%{filtro}%"),
    )
    return [{"tabela": t, "linhas_aprox": n, "descricao": d} for t, n, d in linhas]


@mcp.tool(annotations=LEITURA)
def descrever_tabela(schema: str, tabela: str) -> list[dict]:
    """Colunas e tipos de uma tabela."""
    if schema not in SCHEMAS:
        raise ValueError(f"schema deve ser um de {SCHEMAS}")
    _, linhas = _consultar(
        """SELECT column_name, data_type, is_nullable FROM information_schema.columns
           WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position""",
        (schema, tabela),
    )
    if not linhas:
        raise ValueError(f"tabela {schema}.{tabela} não encontrada")
    return [{"coluna": c, "tipo": t, "aceita_nulo": n == "YES"} for c, t, n in linhas]


@mcp.tool(annotations=LEITURA)
def consultar(sql: str, limite: int = 200) -> dict:
    """Executa um SELECT (ou WITH ... SELECT) somente leitura e devolve colunas e linhas.
    Devolve no máximo `limite` linhas (até 2000); se houver mais, `truncado` = true."""
    corpo = sql.strip().rstrip(";").strip()
    if not re.match(r"^(select|with)\b", corpo, re.I):
        raise ValueError("só consultas SELECT ou WITH")
    limite = max(1, min(int(limite), LIMITE_MAX))
    colunas, linhas = _consultar(f"SELECT * FROM ({corpo}) AS consulta LIMIT {limite + 1}")
    return {"colunas": colunas, "linhas": linhas[:limite], "truncado": len(linhas) > limite}


def main() -> None:
    if not os.getenv("MCP_DB_PASSWORD"):
        raise SystemExit("MCP_DB_PASSWORD não definida")
    mcp.settings.host = os.getenv("HOST", "0.0.0.0")
    mcp.settings.port = int(os.getenv("PORT", "8083"))
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
