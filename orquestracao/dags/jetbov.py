"""Extração diária do JetBov (fazenda) para raw_jetbov. Ver ingestao/jetbov/extrator.py."""
import os
from datetime import datetime, timedelta

from airflow.sdk import dag, task


@dag(
    schedule="30 4 * * *",  # 04:30 (America/Sao_Paulo), fora do horário de uso do app
    start_date=datetime(2026, 9, 28),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=15)},
    tags=["ingestao", "jetbov", "fazenda"],
)
def jetbov_extracao():
    @task
    def extrair() -> dict:
        from ingestao.jetbov.extrator import executar

        return executar(os.environ["DADOS_DB_URL"], os.environ["JETBOV_USER"], os.environ["JETBOV_PASSWORD"])

    extrair()


jetbov_extracao()
