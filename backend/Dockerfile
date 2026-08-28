FROM python:3.14.4-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY backend/requirements-runtime.txt /app/requirements-runtime.txt
RUN python -m pip install --no-cache-dir --upgrade pip && \
    python -m pip install --no-cache-dir -r /app/requirements-runtime.txt

COPY backend/alembic.ini /app/alembic.ini
COPY backend/alembic /app/alembic
COPY backend/app /app/app
COPY images /app/images

RUN addgroup --system --gid 10001 vdiforge && \
    adduser --system --uid 10001 --ingroup vdiforge --home /nonexistent --no-create-home vdiforge

USER 10001:10001
EXPOSE 8000

CMD ["python", "-m", "uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
