from flask import Flask

from .routes import bp
from .storage import GroupStore


def create_app(store=None):
    """Application factory: keeps the app testable and easy to containerize later."""
    app = Flask(__name__)
    app.config["STORE"] = store or GroupStore()
    app.register_blueprint(bp)
    return app
