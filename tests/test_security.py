"""Security tests: each one proves a finding in SECURITY.md stays fixed.
The "client" fixture lives in tests/conftest.py (runs on memory and Postgres)."""

from app import MAX_REQUEST_BYTES, SECURITY_HEADERS, create_app
from app.services import MAX_AMOUNT, MAX_NAME_LENGTH


def setup_group(c):
    c.post("/groups", json={"name": "Kigali Savers"})
    c.post("/groups/1/members", json={"member": "Aline"})


def post_raw(c, url, raw):
    """Send JSON text exactly as written (json= can't produce NaN/Infinity)."""
    return c.post(url, data=raw, content_type="application/json")


# --- Finding 1: NaN / Infinity amounts were accepted -------------------------
def test_rejects_nan_and_infinity(client):
    setup_group(client)
    for bad in ("NaN", "Infinity", "-Infinity"):
        r = post_raw(client, "/groups/1/contributions", '{"member":"Aline","amount":%s}' % bad)
        assert r.status_code == 400
    # balances must be untouched (and still valid JSON)
    assert client.get("/groups/1").get_json()["total"] == 0


def test_rejects_amount_above_limit(client):
    setup_group(client)
    r = client.post("/groups/1/contributions", json={"member": "Aline", "amount": MAX_AMOUNT + 1})
    assert r.status_code == 400
    r = client.post("/groups/1/contributions", json={"member": "Aline", "amount": MAX_AMOUNT})
    assert r.status_code == 201


# --- Finding 2: no size limits -----------------------------------------------
def test_rejects_long_names(client):
    too_long = "x" * (MAX_NAME_LENGTH + 1)
    assert client.post("/groups", json={"name": too_long}).status_code == 400
    assert client.post("/groups", json={"name": "x" * MAX_NAME_LENGTH}).status_code == 201
    assert client.post("/groups/1/members", json={"member": too_long}).status_code == 400


def test_rejects_non_text_names(client):
    assert client.post("/groups", json={"name": 123}).status_code == 400
    assert client.post("/groups", json={"name": ["a"]}).status_code == 400


def test_rejects_huge_request_body(client):
    r = post_raw(client, "/groups", '{"name":"%s"}' % ("x" * MAX_REQUEST_BYTES))
    assert r.status_code == 413
    assert "error" in r.get_json()


# --- Finding 3: errors were HTML pages ---------------------------------------
def test_errors_are_json(client):
    r = client.get("/no-such-page")
    assert r.status_code == 404 and r.is_json
    r = client.delete("/groups")            # method not allowed
    assert r.status_code == 405 and r.is_json


def test_unexpected_error_hides_details():
    class BrokenStore:
        def list_groups(self):
            raise RuntimeError("password=secret in a database error")

    c = create_app(store=BrokenStore()).test_client()
    r = c.get("/groups")
    assert r.status_code == 500
    assert r.get_json() == {"error": "internal server error"}
    assert b"secret" not in r.data


# --- Finding 4: no security headers ------------------------------------------
def test_security_headers_on_every_response(client):
    for r in (client.get("/health"), client.get("/no-such-page")):
        for name, value in SECURITY_HEADERS.items():
            assert r.headers[name] == value
