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

COPY ingestao /opt/airflow/ingestao
COPY transformacao /opt/airflow/transformacao
COPY orquestracao/dags /opt/airflow/dags
ENV PYTHONPATH=/opt/airflow

# Segredos vêm do serviço "segredos" (Azure Key Vault); ver docker-compose.yml.
COPY infra/segredos/com_segredos.sh orquestracao/entrypoint.sh /opt/airflow/
