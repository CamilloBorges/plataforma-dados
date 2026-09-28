# Imagem do Airflow com as DAGs e o código de ingestão embutidos (sem volume de DAGs:
# cada deploy do EasyPanel reconstrói a imagem a partir do git).
FROM apache/airflow:3.3.2

# Pasta do arquivo de senhas da interface (volume "airflow-auth"): precisa existir na imagem
# com dono airflow, senão o volume nasce como root e o api-server não consegue gravar.
USER root
RUN mkdir -p /opt/airflow/auth && chown airflow:0 /opt/airflow/auth
USER airflow

COPY ingestao/requirements.txt /tmp/requirements-ingestao.txt
RUN pip install --no-cache-dir -r /tmp/requirements-ingestao.txt

COPY ingestao /opt/airflow/ingestao
COPY orquestracao/dags /opt/airflow/dags
ENV PYTHONPATH=/opt/airflow
