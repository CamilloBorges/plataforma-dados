"""Tradução das agendas escritas nos arquivos (tabelas.conf, "-- atualizar:" das views) para o
parâmetro schedule das DAGs. Módulo auxiliar, sem DAG."""
import re

from airflow.sdk import Asset


def schedule(agenda: str):
    """"uma vez" | "Nmin" | "diario HH:MM" | "após <asset>" (roda quando o asset for atualizado)."""
    if agenda == "uma vez":
        return "@once"
    if m := re.fullmatch(r"(\d+)min", agenda):
        return f"*/{m.group(1)} * * * *"
    if m := re.fullmatch(r"diario (\d{2}):(\d{2})", agenda):
        return f"{int(m.group(2))} {int(m.group(1))} * * *"
    if m := re.fullmatch(r"após ([a-z0-9_]+)", agenda):
        return [Asset(m.group(1))]
    raise ValueError(f"agenda inválida: {agenda!r}")


def sufixo(agenda: str) -> str:
    """Parte do dag_id: "diario 03:00" -> "diario_03_00", "após raw_logus_15min" -> "apos_raw_logus_15min"."""
    return re.sub(r"[^a-z0-9]+", "_", agenda.lower().replace("ó", "o")).strip("_")
