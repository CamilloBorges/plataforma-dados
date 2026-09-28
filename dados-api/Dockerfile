# Gateway OData (somente leitura) para o Excel/Power BI, com login do Entra ID. Ver app.py.
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py odata_filter.py ./
EXPOSE 8000
# --proxy-headers: atrás do túnel/Traefik, respeita X-Forwarded-Proto (senão os nextLink saem em http://).
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
