"""Materialização das tabelas api.vw_* (lidas pela API OData do Excel e pelo MCP de SQL).

Uma DAG por agenda declarada no cabeçalho "-- atualizar:" dos arquivos transformacao/api/*.sql.
Ver transformacao/materializar.py.
"""
import os
import re
from datetime import datetime, timedelta

from airflow.sdk import dag, task

from transformacao.materializar import materializar, views


def cron(agenda: str) -> str:
    if agenda == "uma vez":
        return "@once"
    if m := re.fullmatch(r"(\d+)min", agenda):
        return f"*/{m.group(1)} * * * *"
    if m := re.fullmatch(r"diario (\d{2}):(\d{2})", agenda):
        return f"{int(m.group(2))} {int(m.group(1))} * * *"
    raise ValueError(f"agenda inválida: {agenda!r}")


def criar_dag(agenda: str, nomes: list[str]):
    sufixo = re.sub(r"[^a-z0-9]+", "_", agenda.lower()).strip("_")

    @dag(
        dag_id=f"api_views_{sufixo}",
        schedule=cron(agenda),
        start_date=datetime(2026, 9, 28),
        catchup=False,
        max_active_runs=1,
        default_args={"retries": 1, "retry_delay": timedelta(minutes=5)},
        tags=["transformacao", "api"],
    )
    def _dag():
        for nome in nomes:
            @task(task_id=nome)
            def rodar(v: str = nome) -> int:
                return materializar(os.environ["DADOS_DB_URL"], v)

            rodar()

    return _dag()


_por_agenda: dict[str, list[str]] = {}
for _nome, _agenda in views().items():
    _por_agenda.setdefault(_agenda, []).append(_nome)
for _agenda, _nomes in _por_agenda.items():
    globals()[f"dag_{_agenda}"] = criar_dag(_agenda, _nomes)
