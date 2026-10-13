"""Transformações do dbt (transformacao/dbt): "dbt build" = cria os modelos e roda os testes.

Roda depois da cópia diária do Logus (asset raw_logus_diario_03_00). O dbt fica num ambiente
Python próprio (/opt/airflow/dbt-venv, ver orquestracao/Dockerfile) e é chamado como processo separado; a
senha do banco (INGESTAO_DB_PASSWORD) já está no ambiente, posta pelo com_segredos.sh.
"""
import subprocess
from datetime import datetime, timedelta

from airflow.sdk import Asset, dag, task

PROJETO = "/opt/airflow/transformacao/dbt"


@dag(
    dag_id="dbt_build",
    schedule=[Asset("raw_logus_diario_03_00")],
    start_date=datetime(2026, 10, 13),
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(minutes=30),
    tags=["transformacao", "dbt"],
)
def dbt_build():
    @task
    def build() -> None:
        # target e logs fora da pasta da imagem (somente leitura para o usuário airflow).
        subprocess.run(
            ["/opt/airflow/dbt-venv/bin/dbt", "build", "--profiles-dir", PROJETO, "--project-dir", PROJETO,
             "--target-path", "/tmp/dbt/target", "--log-path", "/tmp/dbt/logs"],
            check=True,
        )

    build()


dbt_build()
