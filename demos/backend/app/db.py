"""SQLite 访问层。

设计要点（第 08、14 章会反复用到）：
1. 数据库路径来自环境变量 SQLITE_PATH，绝不硬编码 —— 容器里挂载点固定，宿主机路径随环境变。
2. 每次操作时再读环境变量，而不是 import 时读一次 —— 这样测试可以随时替换路径。
3. 开启 WAL 模式 —— 读写并发更稳，避免"数据库被锁"。
"""

import os
import sqlite3
from pathlib import Path


def db_path() -> str:
    """取数据库文件路径；容器内由 SQLITE_PATH 指向挂载卷。"""
    return os.environ.get("SQLITE_PATH", "./data/app.db")


def get_conn() -> sqlite3.Connection:
    """建立连接。父目录不存在时自动创建，避免首次启动因目录缺失失败。"""
    path = Path(db_path())
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db() -> None:
    """建表 + 灌少量种子数据（只在空表时插入，保证幂等）。"""
    conn = get_conn()
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                title     TEXT    NOT NULL,
                done      INTEGER NOT NULL DEFAULT 0,
                created_at TEXT   NOT NULL DEFAULT (datetime('now', 'localtime'))
            )
            """
        )
        count = conn.execute("SELECT COUNT(*) AS c FROM tasks").fetchone()["c"]
        if count == 0:
            conn.executemany(
                "INSERT INTO tasks (title, done) VALUES (?, ?)",
                [
                    ("把代码推上 Git", 1),
                    ("让流水线自动构建", 0),
                    ("部署到服务器并验证", 0),
                ],
            )
        conn.commit()
    finally:
        conn.close()
