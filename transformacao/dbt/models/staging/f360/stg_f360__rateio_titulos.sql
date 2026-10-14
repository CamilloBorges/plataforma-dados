-- Rateio das parcelas de títulos do F360: uma linha por parcela e linha de rateio (centro de custo,
-- plano de contas, competência). Porta das tabelas f360parcelas/f360titulos/f360parcelasrateio do
-- Fabric. tipo_parcela: Despesa (a pagar) ou Receita (a receber); tipo_rateio pode diferir (ex.: um
-- desconto lançado como receita dentro de uma despesa).
select
    p.parcela_id,
    p.dados -> 'DadosDoTitulo' ->> 'TituloId'           as titulo_id,
    p.tipo                                              as tipo_parcela,
    p.status,
    coalesce(p.cancelada, false)                        as cancelada,
    (p.dados -> 'DadosDoTitulo' ->> 'Emissao')::date    as emissao,
    p.vencimento,
    p.liquidacao,
    p.empresa_cnpj,
    p.cliente_fornecedor                                as pessoa,
    r ->> 'Tipo'                                        as tipo_rateio,
    r ->> 'Competencia'                                 as competencia,
    trim(r ->> 'CentroDeCusto')                         as centro_de_custo,
    r ->> 'PlanoDeContas'                               as plano_de_contas,
    (r ->> 'Valor')::numeric                            as valor
from {{ source('f360', 'parcela_titulo') }} p
cross join lateral jsonb_array_elements(coalesce(p.dados -> 'Rateio', '[]'::jsonb)) r
