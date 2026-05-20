import logging
import os
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import httpx
from azure.cosmos import CosmosClient
from azure.cosmos import exceptions as cosmos_exceptions
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

COSMOS_CONNECTION_STRING = os.getenv("COSMOS_DB_CONNECTION_STRING", "")
DATABASE_NAME = os.getenv("COSMOSDB__DATABASE_NAME", "taskdb")
CONTAINER_NAME = os.getenv("COSMOSDB__CONTAINER_NAME", "tasks")
LABELS_SERVICE_URL = os.getenv("LABELS_SERVICE_URL", "http://labels-api")
ALLOWED_ORIGINS = [o.strip() for o in os.getenv("CORS__ALLOWED_ORIGINS", "").split(",") if o.strip()]

_cosmos_container = None

app_insights_conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
if app_insights_conn:
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor(connection_string=app_insights_conn)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _cosmos_container
    if not COSMOS_CONNECTION_STRING:
        raise RuntimeError(
            "COSMOS_DB_CONNECTION_STRING is not configured. "
            "Set it to the Cosmos DB primary connection string."
        )
    logger.info("Connecting to Cosmos DB database=%s container=%s", DATABASE_NAME, CONTAINER_NAME)
    client = CosmosClient.from_connection_string(COSMOS_CONNECTION_STRING)
    db = client.get_database_client(DATABASE_NAME)
    _cosmos_container = db.get_container_client(CONTAINER_NAME)
    logger.info("Cosmos DB connection established")
    yield
    logger.info("Task Manager API shutting down")


app = FastAPI(title="Task Manager API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS if ALLOWED_ORIGINS else ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class CreateTaskRequest(BaseModel):
    title: str
    description: str | None = None
    status: str | None = None


@app.get("/health")
def health(request: Request):
    # X-Forwarded-For is set by App Gateway; fall back to the direct client IP
    forwarded_for = request.headers.get("x-forwarded-for")
    client_ip = forwarded_for.split(",")[0].strip() if forwarded_for else request.client.host
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc),
        "client_ip": client_ip,
        "headers": dict(request.headers),
    }


@app.get("/labels")
async def get_labels():
    """
    Proxies to labels-api via ACA internal service discovery.
    Demonstrates service-to-service communication within the ACA environment.
    """
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(f"{LABELS_SERVICE_URL}/labels")
        response.raise_for_status()
        return response.json()


@app.get("/tasks")
def get_tasks():
    query = "SELECT c.id, c.title, c.description, c.status, c.createdAt FROM c ORDER BY c.createdAt DESC"
    items = list(_cosmos_container.query_items(query=query, enable_cross_partition_query=True))
    logger.info("get_tasks returned %d items", len(items))
    return items


@app.post("/tasks", status_code=201)
async def create_task(request: CreateTaskRequest):
    if not request.title or not request.title.strip():
        raise HTTPException(status_code=400, detail="Title is required.")

    # Validate status against labels-api — ACA internal service call
    valid_labels = ["todo", "in-progress", "done"]
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{LABELS_SERVICE_URL}/labels")
            if resp.status_code == 200:
                valid_labels = resp.json()
    except Exception:
        logger.warning("labels-api unreachable at %s, using fallback labels", LABELS_SERVICE_URL)

    status = (request.status or "todo").strip().lower()
    if status not in valid_labels:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status '{status}'. Valid values from labels-api: {valid_labels}",
        )

    task = {
        "id": uuid.uuid4().hex,
        "title": request.title.strip(),
        "description": request.description,
        "status": status,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    _cosmos_container.create_item(body=task)
    logger.info("Task created id=%s status=%s", task["id"], task["status"])
    return task


@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: str, status: str):
    try:
        _cosmos_container.delete_item(item=task_id, partition_key=status)
        logger.info("Task deleted id=%s", task_id)
    except cosmos_exceptions.CosmosResourceNotFoundError:
        logger.warning("Delete failed: task not found id=%s", task_id)
        raise HTTPException(status_code=404, detail="Task not found.")
