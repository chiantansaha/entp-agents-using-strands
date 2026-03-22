FROM public.ecr.aws/docker/library/python:3.13-slim

RUN pip install uv

WORKDIR /app

COPY pyproject.toml requirements.txt ./
RUN uv pip install --system -r requirements.txt

COPY . .

RUN adduser --disabled-password --gecos '' appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8083

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8083/_stcore/health || exit 1

CMD ["streamlit", "run", "app.py", "--server.port=8083", "--server.address=0.0.0.0"]
