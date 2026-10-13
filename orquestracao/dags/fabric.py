"""Cópia das tabelas do lakehouse do Fabric (OneLake) para raw_fabric. Ver ingestao/fabric/extrator.py.

Às 14:00, depois da cadeia "Atualiza Rentabilidade" do Fabric (11:50), que recalcula o custo do
açougue. O OneLake só responde com a capacidade ligada; se falhar, tenta de novo a cada 30 min.
Publica o asset raw_fabric.
"""
import os
from datetime import datetime, timedelta

from airflow.sdk import Asset, dag, task


@dag(
    schedule="0 14 * * *",
    start_date=datetime(2026, 10, 13),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 3, "retry_delay": timedelta(minutes=30)},
    tags=["ingestao", "fabric", "rentabilidade"],
)
def fabric_extracao():
    @task(outlets=[Asset("raw_fabric")])
    def copiar() -> dict:
        from ingestao.fabric.extrator import executar

        for var in ("FABRIC_TENANT_ID", "FABRIC_CLIENT_ID", "FABRIC_CLIENT_SECRET"):
            if not os.environ.get(var):
                raise RuntimeError(f"{var} não definido: gravar no cofre ({var.lower().replace('_', '-')})")
        return executar(
            os.environ["DADOS_DB_URL"], os.environ["FABRIC_WORKSPACE_ID"], os.environ["FABRIC_LAKEHOUSE_ID"],
            os.environ["FABRIC_TENANT_ID"], os.environ["FABRIC_CLIENT_ID"], os.environ["FABRIC_CLIENT_SECRET"],
        )

    copiar()


fabric_extracao()
