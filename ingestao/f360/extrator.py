"""Extração do F360 Finanças (API pública) para o schema raw_f360. SOMENTE LEITURA.

Fase 1 da integração Logus → F360 (nota "Plataforma de Dados Bomgado" → "Integração Logus → F360"):
só lê o F360 para conferir os dois sistemas; nada é escrito lá. Usa só GET de listagem (o login é
um POST que troca a chave por um JWT).

A cada execução relê as parcelas de títulos (contas a pagar e a receber) com vencimento numa
janela móvel (JANELA_PASSADO dias para trás, JANELA_FUTURO para frente), em janelas de 30 dias
(limite da API), e grava em raw_f360.parcela_titulo por upsert. O que estava na janela e não
voltou nesta leitura (excluído no F360) é apagado. Cadastros (contas, centros de custo, planos)
vão inteiros para raw_f360.cadastro.
"""
import json
import logging
import re
import uuid
from datetime import date, timedelta

import psycopg
import requests

BASE = "https://financas.f360.com.br"
JANELA_DIAS = 30  # a API recusa períodos acima de 31 dias
JANELA_PASSADO = 180
JANELA_FUTURO = 120
TIPOS = ("Despesa", "Receita")
CADASTROS = {
    "contas_bancarias": "/ContaBancariaPublicAPI/ListarContasBancarias",
    "centros_de_custo": "/CentroDeCustoPublicAPI/ListarCentrosDeCusto",
    "planos_de_contas": "/PlanoDeContasPublicAPI/ListarPlanosContas",
}
PARCELAS = "/ParcelasDeTituloPublicAPI/ListarParcelasDeTitulos"
TIMEOUT = 120

log = logging.getLogger(__name__)

DDL = """
CREATE TABLE IF NOT EXISTS raw_f360.execucao (
    id uuid PRIMARY KEY,
    inicio timestamptz NOT NULL DEFAULT now(),
    fim timestamptz,
    status text NOT NULL DEFAULT 'rodando',
    contagem jsonb,
    erro text
);
CREATE TABLE IF NOT EXISTS raw_f360.parcela_titulo (
    parcela_id text PRIMARY KEY,
    tipo text NOT NULL,
    vencimento date NOT NULL,
    liquidacao date,
    status text,
    valor numeric(14,2),
    numero text,
    cliente_fornecedor text,
    cliente_fornecedor_doc text,
    empresa text,
    empresa_cnpj text,
    conta text,
    meio_pagamento text,
    cancelada boolean,
    dados jsonb NOT NULL,
    visto_em timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS parcela_titulo_venc_idx ON raw_f360.parcela_titulo (tipo, vencimento);
CREATE INDEX IF NOT EXISTS parcela_titulo_numero_idx ON raw_f360.parcela_titulo (tipo, numero);
CREATE TABLE IF NOT EXISTS raw_f360.cadastro (
    nome text PRIMARY KEY,
    extraido_em timestamptz NOT NULL,
    dados jsonb NOT NULL
);
"""


def janelas(inicio: date, fim: date, dias: int = JANELA_DIAS):
    """Divide [inicio, fim] em janelas contíguas de no máximo `dias` dias."""
    atual = inicio
    while atual <= fim:
        termino = min(atual + timedelta(days=dias - 1), fim)
        yield atual, termino
        atual = termino + timedelta(days=1)


def _lista(resultado) -> list:
    """Itens de uma página: o próprio Result, ou o 1º campo-lista dele."""
    if isinstance(resultado, list):
        return resultado
    if isinstance(resultado, dict):
        for valor in resultado.values():
            if isinstance(valor, list):
                return valor
    return []


def _total(resultado) -> int | None:
    if isinstance(resultado, dict):
        for chave, valor in resultado.items():
            if re.match(r"QuantidadeDe(?!Paginas)", chave) and isinstance(valor, int):
                return valor
    return None


class Cliente:
    def __init__(self, api_key: str, sessao: requests.Session | None = None):
        if not api_key:
            raise ValueError("chave da API do F360 vazia")
        self._chave = api_key
        self._s = sessao or requests.Session()
        self._jwt = None

    def _limpo(self, texto: str) -> str:
        return texto.replace(self._chave, "***")[:300]

    def _login(self) -> None:
        r = self._s.post(BASE + "/PublicLoginAPI/DoLogin", json={"token": self._chave}, timeout=60)
        if r.status_code >= 400:
            raise RuntimeError(f"F360 login: HTTP {r.status_code}: {self._limpo(r.text)}")
        self._jwt = r.json()["Token"]

    def get(self, caminho: str, params: dict | None = None):
        """GET autenticado; renova o JWT uma vez em caso de 401. Devolve o Result."""
        for tentativa in (0, 1):
            if self._jwt is None or tentativa == 1:
                self._login()
            r = self._s.get(BASE + caminho, params=params, timeout=TIMEOUT,
                            headers={"Authorization": f"Bearer {self._jwt}"})
            if r.status_code != 401:
                break
        if r.status_code >= 400:
            raise RuntimeError(f"F360 {caminho}: HTTP {r.status_code}: {self._limpo(r.text)}")
        dados = r.json()
        if isinstance(dados, dict):
            if dados.get("Ok") is False:
                raise RuntimeError(f"F360 {caminho} recusou: {self._limpo(str(dados))}")
            return dados.get("Result", dados)
        return dados

    def parcelas(self, tipo: str, inicio: date, fim: date) -> list[dict]:
        """Todas as parcelas de `tipo` com vencimento no período. Falha se a soma das páginas não
        bater com o total que a API informa (não grava lista incompleta sem perceber)."""
        itens: list[dict] = []
        for ini, fi in janelas(inicio, fim):
            pagina, paginas, total, lidos = 1, 1, None, 0
            while pagina <= paginas:
                res = self.get(PARCELAS, {"tipo": tipo, "tipoDatas": "Vencimento", "inicio": ini.isoformat(),
                                          "fim": fi.isoformat(), "pagina": pagina})
                lote = _lista(res)
                if pagina == 1:
                    total = _total(res)
                    paginas = res.get("QuantidadeDePaginas", 1) if isinstance(res, dict) else 1
                itens.extend(lote)
                lidos += len(lote)
                if not lote:
                    break
                pagina += 1
            if total is not None and lidos != total:
                raise RuntimeError(f"F360 {tipo} {ini}..{fi}: {lidos} parcelas lidas, mas a API informa {total}")
        return itens


def _data(valor) -> str | None:
    """'2026-10-02' ou '2026-10-02T00:00:00' -> '2026-10-02'; '' ou None -> None."""
    return valor[:10] if valor else None


def linha(item: dict) -> dict:
    """Colunas de raw_f360.parcela_titulo a partir de um item da API."""
    titulo = item.get("DadosDoTitulo") or {}
    pessoa = titulo.get("ClienteFornecedor") or {}
    empresa = titulo.get("Empresa") or {}
    numero = item.get("Numero") or titulo.get("NumeroDoTitulo")
    return {
        "parcela_id": item["ParcelaId"],
        "tipo": item["Tipo"],
        "vencimento": _data(item["Vencimento"]),
        "liquidacao": _data(item.get("Liquidacao")),
        "status": item.get("Status"),
        "valor": item.get("ValorBruto"),
        "numero": numero.strip() if isinstance(numero, str) else numero,
        "cliente_fornecedor": pessoa.get("Nome"),
        "cliente_fornecedor_doc": pessoa.get("Inscricao"),
        "empresa": empresa.get("Nome"),
        "empresa_cnpj": empresa.get("Inscricao"),
        "conta": item.get("Conta"),
        "meio_pagamento": item.get("MeioDePagamento"),
        "cancelada": item.get("Cancelada"),
        "dados": json.dumps(item, ensure_ascii=False),
    }


COLUNAS = ["parcela_id", "tipo", "vencimento", "liquidacao", "status", "valor", "numero", "cliente_fornecedor",
           "cliente_fornecedor_doc", "empresa", "empresa_cnpj", "conta", "meio_pagamento", "cancelada", "dados"]
UPSERT = (
    f"INSERT INTO raw_f360.parcela_titulo ({', '.join(COLUNAS)}, visto_em) "
    f"VALUES ({', '.join('%(' + c + ')s' for c in COLUNAS)}, %(visto_em)s) "
    "ON CONFLICT (parcela_id) DO UPDATE SET "
    + ", ".join(f"{c} = EXCLUDED.{c}" for c in COLUNAS[1:]) + ", visto_em = EXCLUDED.visto_em"
)


def executar(db_url: str, api_key: str, hoje: date | None = None, cliente: Cliente | None = None) -> dict:
    hoje = hoje or date.today()
    inicio, fim = hoje - timedelta(days=JANELA_PASSADO), hoje + timedelta(days=JANELA_FUTURO)
    f360 = cliente or Cliente(api_key)
    execucao = uuid.uuid4()
    contagem: dict[str, int] = {}
    with psycopg.connect(db_url, autocommit=True) as conn:
        conn.execute(DDL)
        conn.execute("INSERT INTO raw_f360.execucao (id) VALUES (%s)", (execucao,))
        try:
            for nome, caminho in CADASTROS.items():
                dados = f360.get(caminho)
                conn.execute(
                    "INSERT INTO raw_f360.cadastro (nome, extraido_em, dados) VALUES (%s, now(), %s) "
                    "ON CONFLICT (nome) DO UPDATE SET extraido_em = now(), dados = EXCLUDED.dados",
                    (nome, json.dumps(dados, ensure_ascii=False)))
                contagem[nome] = len(_lista(dados))
            for tipo in TIPOS:
                itens = f360.parcelas(tipo, inicio, fim)  # lê tudo antes de mexer na tabela
                with conn.transaction():
                    visto = conn.execute("SELECT clock_timestamp()").fetchone()[0]
                    with conn.cursor() as cur:
                        cur.executemany(UPSERT, [{**linha(i), "visto_em": visto} for i in itens])
                    apagadas = conn.execute(
                        "DELETE FROM raw_f360.parcela_titulo WHERE tipo = %s AND vencimento BETWEEN %s AND %s "
                        "AND visto_em < %s", (tipo, inicio, fim, visto)).rowcount
                contagem[f"parcelas_{tipo.lower()}"] = len(itens)
                contagem[f"apagadas_{tipo.lower()}"] = apagadas
                log.info("F360: %s %d parcelas (%d apagadas)", tipo, len(itens), apagadas)
            conn.execute("UPDATE raw_f360.execucao SET fim = now(), status = 'ok', contagem = %s WHERE id = %s",
                         (json.dumps(contagem), execucao))
        except Exception as e:
            conn.execute("UPDATE raw_f360.execucao SET fim = now(), status = 'erro', erro = %s WHERE id = %s",
                         (str(e)[:2000], execucao))
            raise
    return contagem
