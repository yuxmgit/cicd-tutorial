"""demos 后端接口。

三个必须记住的约定：
1. /healthz 是给流水线和负载均衡用的，不查数据库、不做重活，只回答"我活着"。
2. 业务接口统一挂在 /api 下，方便 Nginx 统一反代。
3. 所有配置来自环境变量，镜像从测试到生产一个字都不改。
"""

import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import db


@asynccontextmanager
async def lifespan(app: FastAPI):
    """启动时初始化数据库；关闭时无需特殊处理。"""
    db.init_db()
    yield


app = FastAPI(title="CI/CD Demo API", version="1.0.0", lifespan=lifespan)


class TaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=100, description="任务标题")


@app.get("/healthz")
def healthz():
    """健康检查：不碰数据库，确保探活本身不会因为依赖故障而误判。"""
    return {"status": "ok", "version": os.environ.get("APP_VERSION", "dev")}


@app.get("/api/tasks")
def list_tasks():
    conn = db.get_conn()
    try:
        rows = conn.execute(
            "SELECT id, title, done, created_at FROM tasks ORDER BY id DESC"
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


@app.post("/api/tasks", status_code=201)
def create_task(payload: TaskIn):
    conn = db.get_conn()
    try:
        cur = conn.execute(
            "INSERT INTO tasks (title, done) VALUES (?, 0)", (payload.title.strip(),)
        )
        conn.commit()
        row = conn.execute(
            "SELECT id, title, done, created_at FROM tasks WHERE id = ?", (cur.lastrowid,)
        ).fetchone()
        return dict(row)
    finally:
        conn.close()


@app.delete("/api/tasks/{task_id}", status_code=204)
def delete_task(task_id: int):
    conn = db.get_conn()
    try:
        cur = conn.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        conn.commit()
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="任务不存在")
        return None
    finally:
        conn.close()
