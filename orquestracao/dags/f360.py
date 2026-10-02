"""Leitura do F360 Finanças para raw_f360 (somente leitura). Ver ingestao/f360/extrator.py.

Publica o asset raw_f360, que dispara as views com "-- atualizar: após raw_f360".
"""
import os
from datetime import datetime, timedelta

from airflow.sdk import Asset, dag, task


@dag(
    schedule="20 6-22 * * *",  # de hora em hora, das 06:20 às 22:20
    start_date=datetime(2026, 10, 1),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 1, "retry_delay": timedelta(minutes=10)},
    tags=["ingestao", "f360", "financeiro"],
)
def f360_leitura():
    @task(outlets=[Asset("raw_f360")])
    def extrair() -> dict:
        from ingestao.f360.extrator import executar

        if not os.environ.get("F360_API_KEY"):
            raise RuntimeError("F360_API_KEY não definido: gravar no cofre (f360-api-key)")
        return executar(os.environ["DADOS_DB_URL"], os.environ["F360_API_KEY"])

    extrair()


f360_leitura()
