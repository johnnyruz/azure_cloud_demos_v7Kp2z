import logging
import os
from datetime import datetime, timezone

from fastapi import FastAPI

app_insights_conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
if app_insights_conn:
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor(connection_string=app_insights_conn)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Labels API", version="1.0.0")

LABELS = ["todo", "in-progress", "done", "cancelled"]


@app.get("/health")
def health():
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc)}


@app.get("/labels")
def get_labels():
    """Return the list of valid task status values."""
    logger.info("Labels requested, returning %d labels", len(LABELS))
    return LABELS
