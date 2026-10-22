import json
import logging
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "webapp"))

from app import client_ip_from, create_app  # noqa: E402


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


@pytest.fixture
def access_lines(caplog):
    """Return the structured access-log entries captured during the test."""
    caplog.set_level(logging.INFO, logger="atdr.access")
    logging.getLogger("atdr.access").propagate = True
    yield lambda: [r.access for r in caplog.records if hasattr(r, "access")]
    logging.getLogger("atdr.access").propagate = False


def test_home_page(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"ATDR Demo Portal" in r.data


def test_health_is_json_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_products_search_filters(client):
    r = client.get("/products?search=lock")
    assert r.status_code == 200
    assert b"Smart Door Lock" in r.data
    assert b"Wi-Fi Router" not in r.data


def test_products_search_is_html_escaped(client):
    r = client.get("/products", query_string={"search": "<script>alert(1)</script>"})
    assert r.status_code == 200
    assert b"<script>alert(1)</script>" not in r.data
    assert b"&lt;script&gt;" in r.data


def test_products_search_is_truncated(client):
    r = client.get("/products", query_string={"search": "a" * 500})
    assert r.status_code == 200
    assert b"a" * 101 not in r.data


def test_login_get_and_post(client):
    assert client.get("/login").status_code == 200
    r = client.post("/login", data={"username": "demo", "password": "S3cret-Never-Logged"})
    assert r.status_code == 200
    assert b"Demo only" in r.data
    assert b"S3cret-Never-Logged" not in r.data


def test_access_log_fields(client, access_lines):
    client.get("/health", headers={"X-Forwarded-For": "203.0.113.7:51234, 10.10.1.4"})
    entry = access_lines()[-1]
    assert set(entry) >= {"timestamp", "request_id", "method", "path", "status", "client_ip"}
    assert entry["method"] == "GET"
    assert entry["path"] == "/health"
    assert entry["status"] == 200
    assert entry["client_ip"] == "203.0.113.7"


def test_access_log_never_contains_secrets(client, access_lines):
    client.post(
        "/login?token=abc123",
        data={"username": "demo", "password": "S3cret-Never-Logged"},
        headers={"Cookie": "session=topsecretcookie", "Authorization": "Bearer xyz"},
    )
    dumped = json.dumps(access_lines())
    for secret in ("S3cret-Never-Logged", "topsecretcookie", "abc123", "Bearer xyz", "demo"):
        assert secret not in dumped


def test_request_id_header(client):
    r = client.get("/")
    assert len(r.headers["X-Request-ID"]) == 36


@pytest.mark.parametrize("xff,expected", [
    (None, "10.0.0.1"),
    ("203.0.113.7", "203.0.113.7"),
    ("203.0.113.7:51234", "203.0.113.7"),
    ("203.0.113.7:51234, 10.10.1.4", "203.0.113.7"),
    ("2001:db8::1", "2001:db8::1"),
    ("[2001:db8::1]:443", "2001:db8::1"),
])
def test_client_ip_from(xff, expected):
    assert client_ip_from(xff, "10.0.0.1") == expected
