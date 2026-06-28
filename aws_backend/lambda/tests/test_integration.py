"""
Integration tests against the live /dev API endpoint.

Required env vars:
  INTEGRATION_BASE_URL   e.g. https://xxx.execute-api.eu-central-1.amazonaws.com/dev
  INTEGRATION_APP_ID     applicationId header value
  INTEGRATION_MEMBER_ID  memberId header value
  INTEGRATION_PASSWORD   password header value (may be empty)
"""
import json
import os

import pytest
import requests

BASE_URL = os.environ.get("INTEGRATION_BASE_URL", "").rstrip("/")
HEADERS = {
    "Content-Type": "application/json",
    "applicationId": os.environ.get("INTEGRATION_APP_ID", ""),
    "memberId": os.environ.get("INTEGRATION_MEMBER_ID", ""),
    "password": os.environ.get("INTEGRATION_PASSWORD", ""),
}


def skip_if_no_url():
    if not BASE_URL:
        pytest.skip("INTEGRATION_BASE_URL not set")


def get(path):
    return requests.get(f"{BASE_URL}{path}", headers=HEADERS, timeout=10)


# ── Existing endpoints (regression guard) ────────────────────────────────────

def test_get_members_returns_200():
    skip_if_no_url()
    r = get("/members")
    assert r.status_code == 200, r.text
    assert isinstance(json.loads(r.text), list)


def test_get_member_by_id_returns_200():
    skip_if_no_url()
    member_id = HEADERS["memberId"]
    r = get(f"/members/{member_id}")
    assert r.status_code == 200, r.text
    body = json.loads(r.text)
    assert "memberId" in body or "name" in body


def test_get_fines_returns_200():
    skip_if_no_url()
    member_id = HEADERS["memberId"]
    r = get(f"/fines?memberId={member_id}")
    assert r.status_code == 200, r.text


def test_get_marschbefehl_returns_200():
    skip_if_no_url()
    r = get("/marschbefehl")
    assert r.status_code == 200, r.text
    assert isinstance(json.loads(r.text), list)


def test_get_docs_returns_200():
    skip_if_no_url()
    r = get("/docs")
    assert r.status_code == 200, r.text


# ── New endpoints ─────────────────────────────────────────────────────────────

def test_get_news_returns_200():
    skip_if_no_url()
    r = get("/news")
    assert r.status_code == 200, r.text
    assert isinstance(json.loads(r.text), list)


def test_get_feedback_returns_200():
    skip_if_no_url()
    r = get("/feedback")
    assert r.status_code == 200, r.text
    assert isinstance(json.loads(r.text), list)


def test_get_legal_returns_200():
    skip_if_no_url()
    r = get("/legal")
    assert r.status_code == 200, r.text
    body = json.loads(r.text)
    assert "datenschutz" in body
    assert "impressum" in body
