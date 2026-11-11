"""接口测试。

注意两点，这两点是"能在 CI 里跑"的关键：
1. 用 tmp_path 隔离数据库，测试之间互不影响，也能并行跑。
2. 通过 monkeypatch 设置环境变量，而不是改代码里的常量。
"""

import importlib

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("SQLITE_PATH", str(tmp_path / "test.db"))
    from app import db, main

    importlib.reload(db)
    importlib.reload(main)
    with TestClient(main.app) as c:  # with 触发 lifespan，自动建表
        yield c


def test_healthz(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_list_seed_tasks(client):
    resp = client.get("/api/tasks")
    assert resp.status_code == 200
    assert len(resp.json()) == 3


def test_create_task(client):
    resp = client.post("/api/tasks", json={"title": "写一条流水线"})
    assert resp.status_code == 201
    assert resp.json()["title"] == "写一条流水线"
    assert resp.json()["done"] == 0


def test_create_task_rejects_empty_title(client):
    resp = client.post("/api/tasks", json={"title": ""})
    assert resp.status_code == 422


def test_delete_task(client):
    created = client.post("/api/tasks", json={"title": "待删除"}).json()
    resp = client.delete(f"/api/tasks/{created['id']}")
    assert resp.status_code == 204


def test_delete_missing_task_returns_404(client):
    resp = client.delete("/api/tasks/99999")
    assert resp.status_code == 404
