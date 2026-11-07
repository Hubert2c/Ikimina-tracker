import os

from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException

from .routes import bp
from .storage import GroupStore, PostgresStore

# Largest request body accepted (16 KB). Bigger requests get 413 before the
# app even reads them, so nobody can exhaust memory with a huge upload.
MAX_REQUEST_BYTES = 16 * 1024

# Headers added to every response (security: tell browsers to be strict).
SECURITY_HEADERS = {
    # Don't guess the content type; trust our "application/json"
    "X-Content-Type-Options": "nosniff",
    # Never show this API inside a frame on another site (clickjacking)
    "X-Frame-Options": "DENY",
    # A JSON API loads no scripts, styles or images, so allow none
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    # Don't send our URLs to other sites
    "Referrer-Policy": "no-referrer",
    # Balances are private financial data: don't keep them in caches
    "Cache-Control": "no-store",
}


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
    app.config["MAX_CONTENT_LENGTH"] = MAX_REQUEST_BYTES
    app.register_blueprint(bp)

    @app.after_request
    def add_security_headers(response):
        # setdefault: keep a header if a route already set it on purpose
        for name, value in SECURITY_HEADERS.items():
            response.headers.setdefault(name, value)
        return response

    @app.errorhandler(HTTPException)
    def http_error(err):
        # Flask's default error pages are HTML. Return JSON instead, so every
        # response from this API has the same shape: {"error": "..."}
        return jsonify(error=err.description), err.code

    @app.errorhandler(Exception)
    def unexpected_error(err):
        # Log the full error on the server, but only send a generic message
        # to the client: stack traces and database errors can leak details.
        app.logger.exception("unhandled error")
        return jsonify(error="internal server error"), 500

    return app
