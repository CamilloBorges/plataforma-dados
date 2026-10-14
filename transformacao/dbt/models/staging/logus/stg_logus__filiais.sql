-- Filiais do Logus, com o CNPJ formatado como o F360 grava (00.000.000/0000-00), para ligar as
-- despesas do F360 à filial.
select
    f.cdg_filial::int                                   as filial_id,
    f.dcr_fantasia                                      as filial,
    f.dcr_razao                                         as razao_social,
    f.nmr_cgc                                           as cnpj,
    regexp_replace(lpad(f.nmr_cgc, 14, '0'), '^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$', '\1.\2.\3/\4-\5') as cnpj_formatado
from {{ source('logus', 'cadfil') }} f
