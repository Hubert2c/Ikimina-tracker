import pytest

from app import create_app


@pytest.fixture
def client():
    return create_app().test_client()


def setup_group(c):
    c.post("/groups", json={"name": "Kigali Savers"})
    c.post("/groups/1/members", json={"member": "Aline"})
    c.post("/groups/1/members", json={"member": "Jean"})


def test_health(client):
    assert client.get("/health").get_json() == {"status": "ok"}


def test_create_group_requires_name(client):
    assert client.post("/groups", json={"name": "  "}).status_code == 400


def test_contribution_flow(client):
    setup_group(client)
    client.post("/groups/1/contributions", json={"member": "Aline", "amount": 5000})
    client.post("/groups/1/contributions", json={"member": "aline", "amount": 2000})
    client.post("/groups/1/contributions", json={"member": "Jean", "amount": 1000})
    r = client.get("/groups/1").get_json()
    assert r["balances"] == {"Aline": 7000, "Jean": 1000}
    assert r["total"] == 8000


def test_rejects_bad_amounts(client):
    setup_group(client)
    for bad in (-5, 0, "100", True, None):
        r = client.post("/groups/1/contributions", json={"member": "Aline", "amount": bad})
        assert r.status_code == 400


def test_rejects_unknown_member(client):
    setup_group(client)
    r = client.post("/groups/1/contributions", json={"member": "Ghost", "amount": 10})
    assert r.status_code == 400


def test_duplicate_member_rejected(client):
    setup_group(client)
    assert client.post("/groups/1/members", json={"member": "ALINE"}).status_code == 400


def test_group_not_found(client):
    assert client.get("/groups/99").status_code == 404


def test_member_balance(client):
    setup_group(client)
    client.post("/groups/1/contributions", json={"member": "Jean", "amount": 300})
    r = client.get("/groups/1/members/jean/balance").get_json()
    assert r == {"member": "Jean", "balance": 300}
    assert client.get("/groups/1/members/nobody/balance").status_code == 404
