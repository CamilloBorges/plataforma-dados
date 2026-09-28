# Plataforma de dados Bomgado

Monorepo da plataforma que substitui o Microsoft Fabric: Postgres + Airflow no EasyPanel.
Documentação e decisões: nota "Plataforma de Dados Bomgado" no cofre do Obsidian.

| Pasta | Conteúdo |
|---|---|
| `docker-compose.yml` | compose do EasyPanel (Postgres 17 + Airflow 3) |
| `infra/` | scripts de 1º boot do banco |
| `ingestao/` | extratores por fonte (código Python puro, testável fora do Airflow) |
| `orquestracao/` | imagem do Airflow e DAGs (só agendam e chamam a ingestão) |
| `transformacao/` | dbt (a criar) |
| `dados-api/` | gateway OData (a migrar do `pleno_db_legado`) |

## Bancos e usuários
- `airflow` (usuário `airflow`): metadados do Airflow.
- `dados`: um schema `raw_<fonte>` por fonte, com dono `ingestao`. Dados brutos como vieram da origem (jsonb), mais a tabela de execuções.

## Fontes
- **JetBov** (`ingestao/jetbov`): API do app web, login com o usuário do Camillo, só GET. DAG `jetbov_extracao`, diária às 04:30.

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
