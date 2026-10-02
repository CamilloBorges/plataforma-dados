# Plataforma de dados Bomgado

Monorepo da plataforma que substitui o Microsoft Fabric: Postgres + Airflow no EasyPanel.
Documentação e decisões: nota "Plataforma de Dados Bomgado" no cofre do Obsidian.

| Pasta | Conteúdo |
|---|---|
| `docker-compose.yml` | compose do EasyPanel (Postgres 17 + Airflow 3) |
| `infra/` | scripts de 1º boot do banco |
| `ingestao/` | extratores por fonte (código Python puro, testável fora do Airflow) |
| `orquestracao/` | imagem do Airflow e DAGs (só agendam e chamam a ingestão) |
| `transformacao/` | views da API (`api/vw_*.sql`) materializadas como tabelas pelo Airflow; dbt depois |
| `dados-api/` | gateway OData do Excel/Power BI (login Entra ID), lê `api.vw_*` |
| `mcp-sql/` | MCP de SQL somente leitura (substitui o Directus/MCP pleno) |
| `infra/directus/`, `infra/postgres/config/` | Directus (`config.bomgado.net`): telas de de/para sobre o schema `config` |

## Bancos e usuários
- `airflow` (usuário `airflow`): metadados do Airflow.
- `dados`: um schema `raw_<fonte>` por fonte, com dono `ingestao`. Dados brutos como vieram da origem (jsonb), mais a tabela de execuções.

## Fontes
- **JetBov** (`ingestao/jetbov`): API do app web, login com o usuário do Camillo, só GET. DAG `jetbov_extracao`, diária às 04:30.
- **Logus / ERP atual** (`ingestao/logus`): Informix `bd_bomgado_m` (rede do Armazém) lido por JDBC (driver da IBM, via JPype), somente leitura e em *dirty read*. Cópia completa com troca atômica para `raw_logus`, conforme `tabelas.conf`: DAG `logus_15min` (vendas, formas de recebimento, estoque) e `logus_diario_03_00` (cadastros). Cada cópia publica o asset `raw_logus_<agenda>`, que dispara as views `api.vw_atual_*` (`-- atualizar: após raw_logus_<agenda>`). Histórico das cargas em `raw_logus.carga`.
- **F360 Finanças** (`ingestao/f360`): leitura da API pública (**somente leitura**; fase 1 da integração Logus → F360). DAG `f360_leitura` de hora em hora (06:20–22:20): parcelas de títulos a pagar e a receber com vencimento de -180 a +120 dias, por upsert em `raw_f360.parcela_titulo` (o que sumiu do F360 na janela é apagado), e cadastros em `raw_f360.cadastro`. Também lê as parcelas de cartões (vendas enviadas pelas adquirentes, últimos 45 dias) em `raw_f360.parcela_cartao` (exige a função "Parcelas de Cartões" liberada na chave; sem ela, a etapa é pulada com aviso). Publica o asset `raw_f360`, que dispara as conferências: `api.vw_boleto_conferencia` (boletos emitidos no Logus × contas a receber do F360; o financeiro do Logus ainda não é usado), `api.vw_compra_conferencia` (notas de entrada do Logus × contas a pagar do F360) e `api.vw_venda_cartao_conferencia` (cartões/vales do PDV × adquirentes no F360, por dia e loja). Chave no cofre: `f360-api-key`.
- **F360, fase 2 (escrita com aprovação)** (`ingestao/f360/envio.py`, DAG `f360_envio`, 06:40–22:40): monta a fila `config.f360_envio` com as pendências das conferências (nota do Logus sem conta a pagar, boleto sem conta a receber), com parcelas da `pagconta`/`recdocob` e plano/centro sugeridos pelo histórico do F360. O Camillo revisa e aprova no **Directus**; a DAG envia só os aprovados pelo webhook de títulos do F360 (`f360-webhook-titulos` no cofre; sem ela, não envia nada) e confirma pela leitura da fase 1.
  - Segredos no cofre: `ifx-user` e `ifx-password`. Host, banco e servidor ficam no compose.
  - **1º deploy:** rodar `logus_diario_03_00` à mão **antes** de ativar `logus_15min` (as views de vendas e estoque juntam os cadastros).

## Configurações de/para (Directus)
- Schema `config`, dono `config_app` (o Directus não enxerga `raw_*`, `legado` nem `api`). As tabelas de negócio ficam versionadas em `infra/postgres/config/*.sql` e são criadas a cada deploy pelo `db-setup`. O Airflow (`ingestao`) e o MCP leem só essas tabelas, nunca as `directus_*`.
- Tabela nova: criar o `.sql` em `infra/postgres/config/`, reimplantar e, no Directus, abrir a coleção para configurar a exibição.
- Segredos no cofre: `directus-db-password`, `directus-secret`, `directus-admin-password` (sem eles o serviço não sobe, mas o resto da plataforma sim). O admin local (`directus-admin@bomgado.com`) é só para emergência.
- Login Entra (OpenID): `directus-entra-client-id`/`-secret` (app "Directus Config", callback `https://config.bomgado.net/auth/login/microsoft/callback`) + `entra-tenant-id`. **Desde a 12.0 o SSO exige licença**: a chave gratuita do Open Innovation Grant vai em `directus-license-key`. Sem chave, o provedor é ignorado (fica só o login local).
- Primeira tabela: `config.depara_produto` (código interno do PlenoKW → `cdg_produto` do Logus).

## Deploy (EasyPanel)
1. Serviço Compose, fonte Git, arquivo `docker-compose.yml` (raiz; o EasyPanel grava o `.env` na raiz e o compose só lê o `.env` da própria pasta).
2. Ambiente: variáveis do `.env.example`.
3. Domínio: serviço `airflow-apiserver`, porta 8080 (criar o domínio **antes** do deploy; ver o gotcha na nota "Infraestrutura Banco Legado PlenoKW").
4. Login: só pelo Cloudflare Access (Entra ID) em `airflow.bomgado.net`; o Airflow não tem senha própria (ver o comentário no compose).

## Testes
```
pip install -r ingestao/requirements.txt pytest
python -m pytest ingestao/tests
```
O teste da troca atômica do Logus usa um Postgres descartável: `TEST_DB_URL=postgresql://... python -m pytest ingestao/tests`.
