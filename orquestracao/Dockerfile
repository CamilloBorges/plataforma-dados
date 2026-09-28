# Imagem do Airflow com as DAGs e o código de ingestão embutidos (sem volume de DAGs:
# cada deploy do EasyPanel reconstrói a imagem a partir do git).
FROM apache/airflow:3.3.2

COPY ingestao/requirements.txt /tmp/requirements-ingestao.txt
RUN pip install --no-cache-dir -r /tmp/requirements-ingestao.txt

COPY ingestao /opt/airflow/ingestao
COPY orquestracao/dags /opt/airflow/dags
ENV PYTHONPATH=/opt/airflow
