# Imagem do Airflow com as DAGs e o código de ingestão embutidos (sem volume de DAGs:
# cada deploy do EasyPanel reconstrói a imagem a partir do git).
FROM apache/airflow:3.3.2

# Java + driver JDBC da IBM para ler o Informix do Logus (ingestao/logus, via JPype).
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends default-jre-headless \
 && rm -rf /var/lib/apt/lists/*
ADD https://repo1.maven.org/maven2/com/ibm/informix/jdbc/4.50.10/jdbc-4.50.10.jar /opt/informix-jdbc/
ADD https://repo1.maven.org/maven2/org/mongodb/bson/3.8.0/bson-3.8.0.jar /opt/informix-jdbc/
RUN chmod 755 /opt/informix-jdbc && chmod 644 /opt/informix-jdbc/*.jar
USER airflow

COPY ingestao/requirements.txt /tmp/requirements-ingestao.txt
RUN pip install --no-cache-dir -r /tmp/requirements-ingestao.txt \
 && python -c "import jpype; print('JVM:', jpype.getDefaultJVMPath())"

# dbt num ambiente Python próprio: as dependências dele (Jinja, protobuf...) não disputam versão
# com as do Airflow. A DAG chama /opt/airflow/dbt-venv/bin/dbt como processo separado.
RUN python -m venv /opt/airflow/dbt-venv \
 && /opt/airflow/dbt-venv/bin/pip install --no-cache-dir "dbt-core~=1.11.0" "dbt-postgres~=1.11.0"

COPY ingestao /opt/airflow/ingestao
# Do usuário airflow: o dbt deps abaixo grava os pacotes dentro do projeto.
COPY --chown=airflow:0 transformacao /opt/airflow/transformacao
# Pacotes do dbt (dbt_utils) baixados no build, não a cada execução. O chmod é preciso porque os
# arquivos podem chegar sem permissão de escrita (cópia a partir do Windows/OneDrive).
RUN chmod -R u+w /opt/airflow/transformacao/dbt \
 && cd /opt/airflow/transformacao/dbt && /opt/airflow/dbt-venv/bin/dbt deps --profiles-dir .
COPY orquestracao/dags /opt/airflow/dags
ENV PYTHONPATH=/opt/airflow

# Segredos vêm do serviço "segredos" (Azure Key Vault); ver docker-compose.yml.
COPY infra/segredos/com_segredos.sh orquestracao/entrypoint.sh /opt/airflow/
