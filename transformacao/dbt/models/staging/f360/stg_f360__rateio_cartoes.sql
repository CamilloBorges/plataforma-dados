-- Rateio das parcelas de cartões do F360: uma linha por parcela e linha de rateio. Nas parcelas de
-- venda (tipo_parcela Receita), a venda entra como receita e a taxa da adquirente como despesa
-- (plano "Taxa Administrativa de Cartões"); as parcelas de tipo Despesa são aluguel de POS e
-- ajustes a débito.
-- Porta das tabelas f360parcelascartoes/f360dadoscaroes/f360parcelascartoesrateio do Fabric.
select
    p.parcela_id,
    p.cartao_id,
    p.dados ->> 'Tipo'                                  as tipo_parcela,
    p.dados ->> 'Status'                                as status,
    coalesce(p.cancelada, false)                        as cancelada,
    p.data_venda,
    p.vencimento,
    p.liquidacao,
    p.empresa_cnpj,
    p.adquirente,
    p.bandeira,
    r ->> 'Tipo'                                        as tipo_rateio,
    r ->> 'Competencia'                                 as competencia,
    trim(r ->> 'CentroDeCusto')                         as centro_de_custo,
    r ->> 'PlanoDeContas'                               as plano_de_contas,
    (r ->> 'Valor')::numeric                            as valor
from {{ source('f360', 'parcela_cartao') }} p
cross join lateral jsonb_array_elements(coalesce(p.dados -> 'Rateio', '[]'::jsonb)) r
