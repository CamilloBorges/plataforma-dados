"""Fase 2 da integração Logus → F360: fila de títulos com aprovação e envio pelo webhook do F360.

ESCREVE NO F360 (só cria títulos; o webhook não altera nem exclui), e só o que o Camillo aprovar
na tabela config.f360_envio (Directus). Autorizado por ele em 02/10/2026, com aprovação por lote.

Etapas (cada uma pode rodar sozinha; a DAG f360_envio chama as três):
  montar_fila  inclui como 'pendente' as pendências novas das conferências (api.vw_compra_conferencia
               "só no Logus" e api.vw_boleto_conferencia "sem título no F360"), com parcelas do Logus
               (pagconta / recdocob) e plano/centro de custo sugeridos pelo histórico do F360;
  enviar       manda cada linha 'aprovado' ao webhook f360-{id}-titulos -> 'enviado' (guarda o rastreioId);
               se o título já existir no F360 (lançado à mão), marca 'confirmado' sem enviar;
  confirmar    procura os 'enviado' em raw_f360.parcela_titulo -> 'confirmado'; sem sinal em 2 dias -> 'erro'.
O webhook é assíncrono (HTTP 200 só confirma o recebimento; o F360 processa em até 1 h), por isso a
confirmação vem da leitura da fase 1, e não da resposta.
"""
import json
import logging
import re

import requests

log = logging.getLogger(__name__)

MEIOS = {"boleto", "dinheiro", "cheque", "dda", "doc/ted", "depósito em conta", "transferência bancária",
         "débito automático", "cartão de crédito / débito", "outros"}
DOCUMENTOS = {"duplicata", "boleto", "nota fiscal", "nota de débito", "conta de consumo", "cupom fiscal",
              "outros", "previsão"}

COMPRAS = """
INSERT INTO config.f360_envio (chave, origem, motivo, tipo_titulo, empresa_cnpj, pessoa_nome, pessoa_doc,
    numero_titulo, tipo_documento, emissao, valor, parcelas, conta_bancaria, meio_pagamento,
    plano_de_contas, centro_de_custo, competencia, historico)
SELECT 'pagar:' || c.cnpj_fornecedor || ':' || c.nota,
       'compra sem título', c.pendencia, 'pagar',
       %(empresa)s, c.fornecedor, c.cnpj_fornecedor, c.nota, 'nota fiscal', c.emissao, c.valor_logus,
       coalesce(p.parcelas, jsonb_build_array(jsonb_build_object(
           'numeroParcela', 1, 'vencimento', c.emissao + 30, 'valor', c.valor_logus, 'codigoDeBarras', NULL))),
       %(conta)s, 'boleto', h.plano, h.centro, to_char(c.emissao, 'MM-YYYY'),
       'Lançado pela plataforma de dados: nota de entrada ' || c.nota || ' do Logus sem título no F360'
FROM api.vw_compra_conferencia c
LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object('numeroParcela', g.n, 'vencimento', g.vencimento, 'valor', g.valor,
                                        'codigoDeBarras', g.barras) ORDER BY g.n) AS parcelas
    FROM (SELECT row_number() OVER (ORDER BY x.dat_vecto, x.nmr_parcela) AS n, x.dat_vecto::date AS vencimento,
                 x.val_pagar AS valor,
                 nullif(trim(coalesce(x.nmr_linha_digitavel, x.cdg_barra, '')), '') AS barras
          FROM raw_logus.pagconta x
          WHERE regexp_replace(x.cdg_fornecedor, '\\D', '', 'g') = c.cnpj_fornecedor
            AND ltrim(x.nmr_docto::text, '0') = c.nota AND x.dat_cancel IS NULL) g
) p ON true
LEFT JOIN LATERAL (
    SELECT r->>'PlanoDeContas' AS plano, r->>'CentroDeCusto' AS centro
    FROM raw_f360.parcela_titulo t, jsonb_array_elements(t.dados->'Rateio') r
    WHERE t.tipo = 'Despesa' AND regexp_replace(t.cliente_fornecedor_doc, '\\D', '', 'g') = c.cnpj_fornecedor
    GROUP BY 1, 2 ORDER BY count(*) DESC LIMIT 1
) h ON true
WHERE c.pendencia LIKE 'só no Logus%%'
  -- nota "comprada" das próprias empresas (Armazém/Bom Kafe) é movimentação interna, não conta a pagar
  AND c.cnpj_fornecedor NOT IN (SELECT regexp_replace(nmr_cgc::text, '\\D', '', 'g') FROM raw_logus.cadfil)
ON CONFLICT (chave) DO NOTHING
"""

BOLETOS = """
INSERT INTO config.f360_envio (chave, origem, motivo, tipo_titulo, empresa_cnpj, pessoa_nome, pessoa_doc,
    numero_titulo, tipo_documento, emissao, valor, parcelas, conta_bancaria, meio_pagamento,
    plano_de_contas, centro_de_custo, competencia, historico)
SELECT 'receber:boleto:' || b.id, 'boleto sem título', b.pendencia, 'receber',
       %(empresa)s, coalesce(nullif(trim(cl.dcr_fantasia), ''), 'Cliente ' || d.nmr_cliente),
       nullif(regexp_replace(coalesce(cl.cdg_cliente::text, ''), '\\D', '', 'g'), ''),
       b.id, 'boleto', b.emissao, b.valor,
       jsonb_build_array(jsonb_build_object('numeroParcela', 1, 'vencimento', b.vencimento, 'valor', b.valor,
                                            'codigoDeBarras', NULL)),
       %(conta)s, 'boleto', 'Vendas de Mercadorias', %(centro)s, to_char(b.emissao, 'MM-YYYY'),
       'Lançado pela plataforma de dados: boleto ' || b.id || ' (nosso número ' || b.nosso_numero || ') do Logus sem título no F360'
FROM api.vw_boleto_conferencia b
JOIN raw_logus.recdocob d ON trim(d.nmr_docto_cob) = b.id
LEFT JOIN raw_logus.cadcli cl ON cl.nmr_cliente = d.nmr_cliente
WHERE b.pendencia = 'sem título no F360' AND b.emissao <= current_date - 2
ON CONFLICT (chave) DO NOTHING
"""

# Padrões do Armazém (empresa que usa o Logus). Conferidos no F360 em 02/10/2026.
EMPRESA = "38.824.899/0001-30"
CONTA = "SANTANDER - ARMAZEM"
CENTRO = "Armazém Bomgado "  # o F360 guarda o nome com espaço no fim


def montar_fila(conn) -> int:
    """Inclui as pendências novas como 'pendente'. Devolve quantas linhas entraram."""
    p = {"empresa": EMPRESA, "conta": CONTA, "centro": CENTRO}
    with conn.transaction():
        n = conn.execute(COMPRAS, p).rowcount + conn.execute(BOLETOS, p).rowcount
    log.info("F360 envio: %d pendências novas na fila", n)
    return n


def _so_digitos(texto) -> str:
    return re.sub(r"\D", "", texto or "")


def payload(linha: dict) -> dict:
    """Título no formato do webhook f360-{id}-titulos. Valida o que o F360 exige (somas que fecham,
    listas fechadas de documento e meio de pagamento, plano de contas). Levanta ValueError com o motivo."""
    faltando = [c for c in ("plano_de_contas", "conta_bancaria", "meio_pagamento", "competencia") if not linha.get(c)]
    if faltando:
        raise ValueError("faltam campos: " + ", ".join(faltando))
    if linha["meio_pagamento"] not in MEIOS:
        raise ValueError(f"meio de pagamento fora da lista do F360: {linha['meio_pagamento']!r}")
    if linha["tipo_documento"] not in DOCUMENTOS:
        raise ValueError(f"tipo de documento fora da lista do F360: {linha['tipo_documento']!r}")
    parcelas = linha["parcelas"] if isinstance(linha["parcelas"], list) else json.loads(linha["parcelas"])
    if not parcelas:
        raise ValueError("sem parcelas")
    valor = round(float(linha["valor"]), 2)
    soma = round(sum(float(p["valor"]) for p in parcelas), 2)
    if abs(soma - valor) > 0.01:
        raise ValueError(f"a soma das parcelas ({soma:.2f}) não fecha com o valor do título ({valor:.2f})")
    doc = _so_digitos(linha.get("pessoa_doc"))
    titulo = {
        "cnpj": linha["empresa_cnpj"],
        "tipoTitulo": linha["tipo_titulo"],
        "numeroTitulo": str(linha["numero_titulo"]),
        "clienteFornecedor": doc if len(doc) in (11, 14) else (linha.get("pessoa_nome") or ""),
        "emissao": str(linha["emissao"])[:10],
        "valor": valor,
        "tipoDocumento": linha["tipo_documento"],
        "contaBancaria": linha["conta_bancaria"],
        "meioPagamento": linha["meio_pagamento"],
        "historico": (linha.get("historico") or "")[:500],
        "parcelas": [],
        "rateio": [],
    }
    if linha.get("pessoa_nome") and len(doc) in (11, 14):
        titulo["detalhesClienteFornecedor"] = {"nome": linha["pessoa_nome"], "cpfCnpj": doc}
    for i, p in enumerate(parcelas, start=1):
        n = int(p.get("numeroParcela") or i)
        v = round(float(p["valor"]), 2)
        titulo["parcelas"].append({"vencimento": str(p["vencimento"])[:10], "valor": v, "numeroParcela": n,
                                   "liquidacao": None, "codigoDeBarras": p.get("codigoDeBarras")})
        rateio = {"competencia": linha["competencia"], "planoDeContas": linha["plano_de_contas"],
                  "numeroParcela": n, "valor": v}
        if linha.get("centro_de_custo"):
            rateio["centroDeCusto"] = linha["centro_de_custo"]
        titulo["rateio"].append(rateio)
    return {"titulos": [titulo]}


JA_NO_F360 = """
SELECT 1 FROM raw_f360.parcela_titulo
WHERE tipo = %(tipo)s AND NOT coalesce(cancelada, false)
  AND ltrim(regexp_replace(coalesce(numero, ''), '\\D', '', 'g'), '0') = ltrim(regexp_replace(%(numero)s, '\\D', '', 'g'), '0')
  AND (%(doc)s = '' OR regexp_replace(coalesce(cliente_fornecedor_doc, ''), '\\D', '', 'g') = %(doc)s)
LIMIT 1
"""


def _ja_no_f360(conn, linha: dict) -> bool:
    tipo = "Despesa" if linha["tipo_titulo"] == "pagar" else "Receita"
    return conn.execute(JA_NO_F360, {"tipo": tipo, "numero": str(linha["numero_titulo"]),
                                     "doc": _so_digitos(linha.get("pessoa_doc"))}).fetchone() is not None


def enviar(conn, url: str, post=requests.post) -> dict:
    """Manda ao F360 cada linha 'aprovado'. Devolve a contagem por resultado."""
    cur = conn.execute("SELECT * FROM config.f360_envio WHERE status = 'aprovado' ORDER BY id")
    colunas = [c.name for c in cur.description]
    resultado = {"enviados": 0, "ja_existiam": 0, "erros": 0}
    for valores in cur.fetchall():
        linha = dict(zip(colunas, valores))
        if _ja_no_f360(conn, linha):
            conn.execute("UPDATE config.f360_envio SET status = 'confirmado', confirmado_em = now(), "
                         "erro = 'já existia no F360; não foi enviado' WHERE id = %s", (linha["id"],))
            resultado["ja_existiam"] += 1
            continue
        try:
            corpo = payload(linha)
            r = post(url, json=corpo, timeout=60)
            if r.status_code >= 300:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
            rastreio = (r.json() or {}).get("rastreioId")
        except Exception as e:  # noqa: BLE001 - registra o motivo na linha e segue para a próxima
            conn.execute("UPDATE config.f360_envio SET status = 'erro', erro = %s WHERE id = %s",
                         (str(e)[:1000], linha["id"]))
            resultado["erros"] += 1
            continue
        conn.execute("UPDATE config.f360_envio SET status = 'enviado', enviado_em = now(), rastreio_id = %s, "
                     "erro = NULL WHERE id = %s", (rastreio, linha["id"]))
        resultado["enviados"] += 1
    log.info("F360 envio: %s", resultado)
    return resultado


def confirmar(conn) -> dict:
    """Confere os 'enviado' na leitura do F360 (raw_f360)."""
    cur = conn.execute("SELECT * FROM config.f360_envio WHERE status = 'enviado'")
    colunas = [c.name for c in cur.description]
    resultado = {"confirmados": 0, "sem_sinal": 0}
    for valores in cur.fetchall():
        linha = dict(zip(colunas, valores))
        if _ja_no_f360(conn, linha):
            conn.execute("UPDATE config.f360_envio SET status = 'confirmado', confirmado_em = now() WHERE id = %s",
                         (linha["id"],))
            resultado["confirmados"] += 1
        else:
            conn.execute("UPDATE config.f360_envio SET status = 'erro', erro = 'não apareceu no F360 em 2 dias "
                         "(ver a tela Upload de Arquivos do F360)' WHERE id = %s AND enviado_em < now() - interval '2 days'",
                         (linha["id"],))
            resultado["sem_sinal"] += 1
    return resultado
