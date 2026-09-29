"""Cópia do ERP atual (Informix/Logus) para raw_logus. Ver ingestao/logus/extrator.py.

Uma DAG logus_<agenda> por agenda do ingestao/logus/tabelas.conf. Ao terminar sem erro, a tarefa
atualiza o asset raw_logus_<agenda>, que dispara as views "-- atualizar: após raw_logus_<agenda>".
"""
import os
from datetime import datetime, timedelta

from airflow.sdk import Asset, dag, task

from agenda import schedule, sufixo
from ingestao.logus.extrator import tabelas


def criar_dag(agenda: str):
    nome = sufixo(agenda)

    @dag(
        dag_id=f"logus_{nome}",
        schedule=schedule(agenda),
        start_date=datetime(2026, 9, 30),
        catchup=False,
        max_active_runs=1,
        dagrun_timeout=timedelta(minutes=30),
        default_args={"retries": 1, "retry_delay": timedelta(minutes=2)},
        tags=["ingestao", "logus", "armazem"],
    )
    def _dag():
        @task(outlets=[Asset(f"raw_logus_{nome}")])
        def copiar() -> dict:
            from ingestao.logus.extrator import executar

            for var in ("IFX_USER", "IFX_PASSWORD"):
                if not os.environ.get(var):
                    raise RuntimeError(f"{var} não definido: gravar no cofre ({var.lower().replace('_', '-')})")
            return executar(
                os.environ["DADOS_DB_URL"], agenda,
                os.environ["IFX_HOST"], os.environ["IFX_DB"], os.environ["IFX_SERVER"],
                os.environ["IFX_USER"], os.environ["IFX_PASSWORD"],
            )

        copiar()

    return _dag()


for _agenda in sorted(set(tabelas().values())):
    globals()[f"dag_logus_{sufixo(_agenda)}"] = criar_dag(_agenda)
