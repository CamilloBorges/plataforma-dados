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

## Bancos e usuários
- `airflow` (usuário `airflow`): metadados do Airflow.
- `dados`: um schema `raw_<fonte>` por fonte, com dono `ingestao`. Dados brutos como vieram da origem (jsonb), mais a tabela de execuções.

## Fontes
- **JetBov** (`ingestao/jetbov`): API do app web, login com o usuário do Camillo, só GET. DAG `jetbov_extracao`, diária às 04:30.
- **Logus / ERP atual** (`ingestao/logus`): Informix `bd_bomgado_m` (rede do Armazém) lido por JDBC (driver da IBM, via JPype), somente leitura e em *dirty read*. Cópia completa com troca atômica para `raw_logus`, conforme `tabelas.conf`: DAG `logus_15min` (vendas, formas de recebimento, estoque) e `logus_diario_03_00` (cadastros). Cada cópia publica o asset `raw_logus_<agenda>`, que dispara as views `api.vw_atual_*` (`-- atualizar: após raw_logus_<agenda>`). Histórico das cargas em `raw_logus.carga`.
  - Segredos no cofre: `ifx-user` e `ifx-password`. Host, banco e servidor ficam no compose.
  - **1º deploy:** rodar `logus_diario_03_00` à mão **antes** de ativar `logus_15min` (as views de vendas e estoque juntam os cadastros).

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
