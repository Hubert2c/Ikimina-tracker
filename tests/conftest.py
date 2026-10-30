"""Shared test fixtures.

Every test runs against the in-memory store. If TEST_DATABASE_URL is set
(it is in CI, which starts a PostgreSQL service), every test ALSO runs against
PostgreSQL, so we know both storage backends behave the same way.
"""
import os

import pytest

from app import create_app
from app.storage import GroupStore

TEST_DB_URL = os.environ.get("TEST_DATABASE_URL")

# Which backends to test: always "memory", plus "postgres" when a DB is available
BACKENDS = ["memory"] + (["postgres"] if TEST_DB_URL else [])


def _make_store(backend):
    if backend == "memory":
        return GroupStore()

    from app.storage import PostgresStore

    store = PostgresStore(TEST_DB_URL)
    # Start each test with empty tables and ids starting again at 1
    with store._connect() as conn:
        conn.execute("TRUNCATE groups, members, contributions RESTART IDENTITY CASCADE")
    return store


@pytest.fixture(params=BACKENDS)
def client(request):
    return create_app(store=_make_store(request.param)).test_client()
