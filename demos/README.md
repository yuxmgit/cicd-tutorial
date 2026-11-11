# demos 示例项目

一个"能在 5 分钟内跑起来、也能被流水线部署"的最小全栈应用：

- 前端 `frontend/`：Vue 3 + Vite，任务清单页面
- 后端 `backend/`：FastAPI + SQLite，提供 `/api/tasks` 与 `/healthz`

## 一、目录

```
demos/
├── frontend/
│   ├── package.json        依赖与脚本：dev / build / lint / test
│   ├── vite.config.js      开发代理、构建、单测覆盖率门槛
│   ├── eslint.config.js    代码规范
│   └── src/
│       ├── App.vue         页面
│       ├── main.js         入口
│       ├── style.css       样式
│       └── __tests__/      组件单测
└── backend/
    ├── requirements.txt    锁版本依赖
    ├── pytest.ini          测试 + 覆盖率门槛 80%
    ├── app/
    │   ├── main.py         接口 + /healthz
    │   └── db.py           SQLite（路径来自 SQLITE_PATH）
    └── tests/test_api.py   接口测试
```

## 二、本地起后端

```powershell
cd I:\work-body-dir\cicd-tutorial\demos\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:SQLITE_PATH=".\data\app.db"
uvicorn app.main:app --reload --port 8000
```

验证（另开一个终端）：

```powershell
curl.exe http://127.0.0.1:8000/healthz
curl.exe http://127.0.0.1:8000/api/tasks
```

预期：

```json
{"status":"ok","version":"dev"}
[{"id":3,"title":"部署到服务器并验证","done":0,"created_at":"..."}]
```

## 三、本地起前端

```powershell
cd I:\work-body-dir\cicd-tutorial\demos\frontend
npm install
npm run dev
```

打开 http://127.0.0.1:5173 ，应看到任务清单页面；添加、删除任务都会打到后端。

> 前端开发时请求 `/api` 由 Vite 代理转发到 `127.0.0.1:8000`，所以不需要配 CORS。

## 四、跑质量检查（第 07、09 章会接进流水线）

```powershell
# 前端
cd demos\frontend
npm run lint
npm run test
npm run build

# 后端
cd demos\backend
pytest
```

三条命令都应该是绿的。红的那条就是你的流水线将来会拦住你的地方。

## 五、常见问题

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `npm run dev` 后页面 404 接口 | 后端没起或端口不是 8000 | 先起后端，`curl /healthz` 确认 |
| `pytest` 报覆盖率低于 80% | 新增代码没写测试 | 补测试，或在 `pytest.ini` 临时调阈值（第 09 章讲怎么定合理阈值） |
| SQLite 报 `database is locked` | 多进程同时写 | 单 worker 运行；已开 WAL，读多写少场景足够 |
| Windows 上 shell 脚本跑不了 | 用了 PowerShell 跑 `.sh` | 改用 Git Bash |
