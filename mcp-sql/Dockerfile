# MCP somente leitura sobre o Postgres da plataforma (substitui o Directus/MCP pleno). Ver server.py.
FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY server.py .
RUN useradd --system --uid 1000 appuser
USER appuser
EXPOSE 8083
CMD ["python", "server.py"]
