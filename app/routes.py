import os

from flask import Blueprint, current_app, jsonify, request

from . import services

bp = Blueprint("api", __name__)


def _store():
    return current_app.config["STORE"]


def _body():
    return request.get_json(silent=True) or {}


@bp.errorhandler(services.ValidationError)
def _bad_request(err):
    return jsonify(error=str(err)), 400


@bp.errorhandler(services.NotFoundError)
def _not_found(err):
    return jsonify(error=str(err)), 404


@bp.get("/health")
def health():
    """Liveness: the process is up and answering. Never touches the database,
    so a database outage doesn't make Docker restart a healthy app."""
    return jsonify(status="ok")


@bp.get("/ready")
def ready():
    """Readiness: the app can do real work, i.e. the database answers.
    503 tells an operator (or a load balancer) not to send traffic yet."""
    try:
        _store().ping()
    except Exception:
        # Log the real reason on the server; send only a short status out
        current_app.logger.exception("readiness check failed")
        return jsonify(status="unavailable", database="unreachable"), 503
    return jsonify(status="ready", database="ok")


@bp.get("/version")
def version():
    """Which build is running. The deployment pipeline sets APP_VERSION
    (e.g. to the git commit SHA), so after a deploy you can confirm the
    new code is live by comparing this value with the commit on GitHub."""
    return jsonify(version=os.environ.get("APP_VERSION", "dev"))


@bp.get("/groups")
def list_groups():
    return jsonify([{"id": g["id"], "name": g["name"]} for g in _store().list_groups()])


@bp.post("/groups")
def create_group():
    group = services.create_group(_store(), _body().get("name"))
    return jsonify(group), 201


@bp.post("/groups/<int:gid>/members")
def add_member(gid):
    group = services.add_member(_store(), gid, _body().get("member"))
    return jsonify(group), 201


@bp.post("/groups/<int:gid>/contributions")
def add_contribution(gid):
    data = _body()
    group = services.add_contribution(_store(), gid, data.get("member"), data.get("amount"))
    return jsonify(group), 201


@bp.get("/groups/<int:gid>")
def get_group(gid):
    return jsonify(services.summary(_store(), gid))


@bp.get("/groups/<int:gid>/members/<member>/balance")
def get_balance(gid, member):
    return jsonify(services.member_balance(_store(), gid, member))
