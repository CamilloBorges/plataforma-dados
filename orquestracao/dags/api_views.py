"""Materialização das tabelas api.vw_* (lidas pela API OData do Excel e pelo MCP de SQL).

Uma DAG por agenda declarada no cabeçalho "-- atualizar:" dos arquivos transformacao/api/*.sql
(ver agenda.py; "após raw_logus_15min" roda logo depois de cada cópia do Logus).
Ver transformacao/materializar.py.
"""
import os
from datetime import datetime, timedelta

from airflow.sdk import dag, task

from agenda import schedule, sufixo
from transformacao.materializar import materializar, views


def criar_dag(agenda: str, nomes: list[str]):
    @dag(
        dag_id=f"api_views_{sufixo(agenda)}",
        schedule=schedule(agenda),
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
