import os

from flask import Flask

from .routes import bp
from .storage import GroupStore, PostgresStore


def _default_store():
    """Pick the storage backend from the environment.

    DATABASE_URL set (e.g. by docker-compose)  -> PostgreSQL
    DATABASE_URL not set (tests, quick runs)   -> in-memory
    """
    url = os.environ.get("DATABASE_URL")
    return PostgresStore(url) if url else GroupStore()


def create_app(store=None):
    """Application factory: keeps the app testable and easy to containerize."""
    app = Flask(__name__)
    app.config["STORE"] = store or _default_store()
    app.register_blueprint(bp)
    return app
