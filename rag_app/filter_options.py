"""Options for the UI filters (companies, source types, years), read from Databricks tables.

Tables are read through a SQL warehouse (a Mac cannot run SQL on Databricks without one).
The result is cached in memory for the lifetime of the API process:
restart the API to pick up changes in silver.company or silver.doc_chunks.

Warehouse: set RAG_WAREHOUSE_ID, otherwise the first warehouse in the workspace is used
(on Free Edition that is the "Serverless Starter Warehouse").
"""

from __future__ import annotations

import os
import time
from functools import lru_cache

from databricks.sdk.service.sql import StatementState

from rag_app.rag import get_client

SILVER = os.getenv("RAG_SILVER_SCHEMA", "humanoid_robotics.silver")

# Only companies that appear in at least one indexed chunk (others would return no results)
COMPANIES_SQL = f"""
SELECT c.company_id, c.company_name, c.company_type
FROM {SILVER}.company c
WHERE EXISTS (
    SELECT 1 FROM {SILVER}.doc_chunks d
    WHERE array_contains(split(d.company_ids, ' '), c.company_id)
)
ORDER BY c.company_name
"""

DOC_ATTRIBUTES_SQL = f"""
SELECT DISTINCT source_type, publish_year
FROM {SILVER}.doc_chunks
"""


def _warehouse_id() -> str:
    warehouse_id = os.getenv("RAG_WAREHOUSE_ID")
    if warehouse_id:
        return warehouse_id
    for warehouse in get_client().warehouses.list():
        return warehouse.id
    raise RuntimeError("No SQL warehouse found. Create one or set RAG_WAREHOUSE_ID.")


def _run_sql(statement: str, timeout_s: int = 120) -> list[dict]:
    """Run one SQL statement on the warehouse and return rows as dicts.
    A stopped serverless warehouse first starts up, so we poll until the query finishes."""
    w = get_client()
    response = w.statement_execution.execute_statement(
        statement=statement, warehouse_id=_warehouse_id(), wait_timeout="30s",
    )
    deadline = time.time() + timeout_s
    while response.status.state in (StatementState.PENDING, StatementState.RUNNING):
        if time.time() > deadline:
            raise TimeoutError("SQL warehouse query timed out")
        time.sleep(2)
        response = w.statement_execution.get_statement(response.statement_id)

    if response.status.state != StatementState.SUCCEEDED:
        error = response.status.error.message if response.status.error else response.status.state
        raise RuntimeError(f"SQL query failed: {error}")

    columns = [c.name for c in response.manifest.schema.columns]
    rows = (response.result.data_array or []) if response.result else []
    return [dict(zip(columns, row)) for row in rows]


@lru_cache(maxsize=1)
def get_filter_options() -> dict:
    """Read once per API process, then served from memory.
    (lru_cache does not store errors, so a failed read is retried on the next call.)"""
    companies = _run_sql(COMPANIES_SQL)
    doc_rows = _run_sql(DOC_ATTRIBUTES_SQL)

    return {
        "companies": companies,
        "company_types": sorted({c["company_type"] for c in companies if c["company_type"]}),
        "source_types": sorted({r["source_type"] for r in doc_rows if r["source_type"]}),
        "years": sorted({int(r["publish_year"]) for r in doc_rows if r["publish_year"]},
                        reverse=True),
    }
