"""Extração do JetBov (API usada pelo app web app.jetbov.com) para o schema raw_jetbov.

Somente leitura: faz login com o usuário do Camillo e só chama GET. Grava cada resposta
como veio (jsonb), sem transformar; a modelagem fica para a camada de transformação.
Mapeamento das rotas: nota "Integração JetBov (API do app)" no cofre.
"""
import json
import logging
import os
import uuid

import psycopg
import requests

BASE = "https://api.jetbov.com/api/"
TIMEOUT = 180  # animal/ e sale/ levam ~60 s no servidor do JetBov

# Cadastros: a lista inteira vem numa chamada.
CADASTROS = [
    "myfarm/",
    "herd/",
    "pastures/",
    "animal/",
    "inventoryReport/",
    "purchase/",
    "sale/",
    "costEvent/",
    "stocks/",
    "breed/",
    "animalcategory/",
    "finance_account/",
    "semenRegistry/",
    "reports/weight/",
]

# Eventos paginados: endpoint -> chave da lista na resposta. Respondem com
# meta{total_pages}; a tela só mostra confirmed=False, então buscamos os dois.
# endpoint -> (chave da lista na resposta, aceita o filtro confirmed?).
# 28/09: healthEvents respeita confirmed (a tela só mostra False); nutritionEvents ignora o
# filtro (True e False devolvem a mesma lista) e a paginação não tem ordem estável (páginas de
# 100 repetiram registros e perderam 90 de 1.213). Por isso páginas grandes + conferência de IDs.
PAGINADOS = {
    "healthEvents/": ("health_events", True),
    "nutritionEvents/": ("nutritions", False),
}
POR_PAGINA = 5000

log = logging.getLogger(__name__)

DDL = """
CREATE TABLE IF NOT EXISTS raw_jetbov.execucao (
    id uuid PRIMARY KEY,
    inicio timestamptz NOT NULL DEFAULT now(),
    fim timestamptz,
    status text NOT NULL DEFAULT 'rodando',
    erro text
);
CREATE TABLE IF NOT EXISTS raw_jetbov.resposta (
    id bigserial PRIMARY KEY,
    execucao uuid NOT NULL REFERENCES raw_jetbov.execucao(id),
    endpoint text NOT NULL,
    parametros jsonb NOT NULL DEFAULT '{}',
    extraido_em timestamptz NOT NULL DEFAULT now(),
    dados jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS resposta_endpoint_idx ON raw_jetbov.resposta (endpoint, extraido_em DESC);
"""


def login(sessao: requests.Session, usuario: str, senha: str) -> None:
    r = sessao.post(BASE + "api-token-auth/", json={"username": usuario, "password": senha}, timeout=60)
    r.raise_for_status()
    corpo = r.json()
    token = corpo.get("Token") or corpo.get("token")
    if not token:
        raise RuntimeError(f"login sem token; chaves da resposta: {sorted(corpo)}")
    sessao.headers["Authorization"] = f"Token {token}"  # confirmado em 28/09: Bearer/JWT dão 401


def buscar(sessao: requests.Session, endpoint: str, parametros: dict | None = None):
    r = sessao.get(BASE + endpoint, params=parametros, timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()


def paginas(sessao: requests.Session, endpoint: str, chave: str, usa_confirmado: bool):
    """Gera (parametros, dados) de todas as páginas. Falha se os IDs distintos não baterem
    com o total informado pela API (evita gravar lista incompleta sem perceber)."""
    filtros = [{"confirmed": "True"}, {"confirmed": "False"}] if usa_confirmado else [{}]
    ids, total_api = set(), 0
    for filtro in filtros:
        pagina, total_paginas = 1, 1
        while pagina <= total_paginas:
            parametros = {**filtro, "page": pagina, "per_page": POR_PAGINA}
            dados = buscar(sessao, endpoint, parametros)
            if chave not in dados:
                raise RuntimeError(f"{endpoint}: resposta sem '{chave}' (chaves: {sorted(dados)})")
            meta = dados.get("meta", {})
            total_paginas = meta.get("total_pages", 1)
            if pagina == 1:
                total_api += meta.get("total_results", 0)
            ids.update(item.get("id") for item in dados[chave])
            yield parametros, dados
            pagina += 1
    if len(ids) != total_api:
        raise RuntimeError(f"{endpoint}: {len(ids)} IDs distintos, mas a API informa {total_api}")


def executar(db_url: str, usuario: str, senha: str) -> dict:
    """Extrai tudo e grava em raw_jetbov. Devolve {endpoint: nº de respostas gravadas}."""
    execucao = uuid.uuid4()
    contagem: dict[str, int] = {}
    with psycopg.connect(db_url, autocommit=True) as conn:
        conn.execute(DDL)
        conn.execute("INSERT INTO raw_jetbov.execucao (id) VALUES (%s)", (execucao,))

        def gravar(endpoint, parametros, dados):
            conn.execute(
                "INSERT INTO raw_jetbov.resposta (execucao, endpoint, parametros, dados) VALUES (%s, %s, %s, %s)",
                (execucao, endpoint, json.dumps(parametros or {}), json.dumps(dados)),
            )
            contagem[endpoint] = contagem.get(endpoint, 0) + 1

        try:
            sessao = requests.Session()
            sessao.headers["Content-Type"] = "application/json"
            sessao.headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36"  
            login(sessao, usuario, senha)
            for endpoint in CADASTROS:
                log.info("JetBov: %s", endpoint)
                gravar(endpoint, None, buscar(sessao, endpoint))
            for endpoint, (chave, usa_confirmado) in PAGINADOS.items():
                for parametros, dados in paginas(sessao, endpoint, chave, usa_confirmado):
                    log.info("JetBov: %s %s", endpoint, parametros)
                    gravar(endpoint, parametros, dados)
        except Exception as e:
            conn.execute(
                "UPDATE raw_jetbov.execucao SET fim = now(), status = 'erro', erro = %s WHERE id = %s",
                (repr(e)[:2000], execucao),
            )
            raise
        conn.execute("UPDATE raw_jetbov.execucao SET fim = now(), status = 'ok' WHERE id = %s", (execucao,))
    return contagem


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    print(executar(os.environ["DADOS_DB_URL"], os.environ["JETBOV_USER"], os.environ["JETBOV_PASSWORD"]))
