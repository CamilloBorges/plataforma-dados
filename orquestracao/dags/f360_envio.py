"""Fase 2 da integração Logus → F360: fila de títulos com aprovação (Directus) e envio pelo webhook.
Ver ingestao/f360/envio.py. Sem a URL do webhook no cofre (f360-webhook-titulos), só monta a fila
e confere; não envia nada.
"""
import os
from datetime import datetime, timedelta

from airflow.sdk import dag, task


@dag(
    schedule="40 6-22 * * *",  # de hora em hora, 20 min depois da leitura do F360 (f360_leitura)
    start_date=datetime(2026, 10, 1),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 1, "retry_delay": timedelta(minutes=10)},
    tags=["f360", "financeiro", "escrita"],
)
def f360_envio():
    @task
    def executar() -> dict:
        import psycopg

        from ingestao.f360.envio import confirmar, enviar, montar_fila

        with psycopg.connect(os.environ["DADOS_DB_URL"], autocommit=True) as conn:
            saida = {"novos_na_fila": montar_fila(conn), "confirmacao": confirmar(conn)}
            url = os.environ.get("F360_WEBHOOK_TITULOS")
            saida["envio"] = enviar(conn, url) if url else "sem URL do webhook no cofre: nada enviado"
        return saida

    executar()


f360_envio()
