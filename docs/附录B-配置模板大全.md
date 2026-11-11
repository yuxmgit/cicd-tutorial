# 附录 B 配置模板大全

> 每个模板都对应正文某一章的完整讲解。此页是"拿来即用"的汇总，修改处用 `# ←` 标注。

## B1 Docker daemon（服务器 `/etc/docker/daemon.json`，第 11 章）

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "registry-mirrors": ["https://mirror.ccs.tencentyun.com"]
}
```

## B2 生产 compose（`deploy/docker-compose.prod.yml` 精简骨架，第 12 章）

```yaml
name: cicd-demo                    # 固定 project 名，防 project 并存
services:
  api:
    image: ${REGISTRY}/${NAMESPACE}/cicd-demo-backend:${IMAGE_TAG:?}
    restart: unless-stopped
    ports: ["127.0.0.1:8000:8000"]  # 只绑回环，公网走 Nginx
    volumes:
      - ${APP_BASE_DIR}/shared/data:/data
    stop_grace_period: 30s
    logging: { driver: json-file, options: { max-size: "10m", max-file: "3" } }
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz',timeout=2).status==200 else 1)\""]
      interval: 30s
      start_period: 15s
      retries: 3
  web:
    image: ${REGISTRY}/${NAMESPACE}/cicd-demo-frontend:${IMAGE_TAG:?}
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes:
      - ${APP_BASE_DIR}/shared/nginx/site.conf:/etc/nginx/conf.d/default.conf:ro
      - ${APP_BASE_DIR}/shared/certs:/etc/nginx/certs:ro
    depends_on: [api]
```

## B3 Nginx 站点骨架（`deploy/nginx/site.conf`，第 13 章）

```nginx
server {
    listen 443 ssl; http2 on;
    ssl_certificate     /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    root  /usr/share/nginx/html;
    client_max_body_size 20m;

    location /api/ {
        proxy_pass http://api:8000;                    # 服务名，不是 127.0.0.1
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location = /index.html { add_header Cache-Control "no-cache"; }
    location ~* \.(js|css|png|svg|woff2?)$ { expires 30d; add_header Cache-Control "public, immutable"; }
    location / { try_files $uri $uri/ /index.html; }   # SPA 回退
}
```

## B4 后端镜像骨架（`deploy/Dockerfile.backend`，第 08 章）

```dockerfile
FROM python:3.11-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 TZ=Asia/Shanghai
WORKDIR /app
FROM base AS deps
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
FROM base AS runtime
COPY --from=deps /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin
COPY app ./app
RUN useradd -m -u 10001 appuser && mkdir -p /data && chown -R appuser:appuser /app /data
USER appuser
ENV SQLITE_PATH=/data/app.db
HEALTHCHECK --interval=30s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz',timeout=2).status==200 else 1)"
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8000","--workers","1","--timeout-graceful-shutdown","20"]
```

## B5 Jenkinsfile 骨架（第 04/15 章）

```groovy
pipeline {
    agent any
    options {
        timestamps()
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
        disableConcurrentBuilds(abortPrevious: true)
    }
    environment {
        GIT_SHA   = sh(returnStdout: true, script: 'git rev-parse --short=7 HEAD').trim()
        IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHA}"
    }
    stages {
        stage('测试')   { steps { dir('demos/backend') { sh 'pytest' } } }
        stage('门禁')   { steps { sh 'bash scripts/security-scan.sh deps' } }
        stage('镜像')   { steps { sh "docker build -f deploy/Dockerfile.backend -t cicd-demo-backend:${env.IMAGE_TAG} demos/backend" } }
        stage('审批')   { when { branch 'main' }; steps { input message: '发布到生产？', submitter: 'release-approvers' } }
        stage('部署')   { steps { sh "ssh yengxun-yun 'TAG=${env.IMAGE_TAG} bash -s' < scripts/deploy-local.sh" } }
    }
    post { failure { echo "失败：${env.BUILD_URL}console" } cleanup { cleanWs() } }
}
```

## B6 防止 CRLF（`.gitattributes`，第 17 章）

```text
* text=auto
*.sh  text eol=lf
*.py  text eol=lf
*.js  text eol=lf
*.groovy text eol=lf
*.yml text eol=lf
*.png binary
```

## B7 测试门禁（pytest.ini / vite.config.js，第 07/08 章）

```ini
[pytest]
testpaths = tests
addopts = -q --cov=app --cov-report=term-missing --cov-fail-under=80
```

```javascript
coverage: {
  provider: 'v8',
  reporter: ['text'],
  thresholds: { lines: 50, functions: 50 }   // 基线法逐步提
}
```

## B8 cron 清单（第 14/18 章）

```bash
10 3  * * * root bash /opt/apps/cicd-demo/scripts/backup-data.sh  >> /var/log/cicd-backup.log 2>&1
0  4  * * 0 root bash /opt/apps/cicd-demo/scripts/cleanup.sh      >> /var/log/cicd-cleanup.log 2>&1
*/5 * * * * root bash /opt/apps/cicd-demo/scripts/mini-monitor.sh >> /var/log/cicd-monitor.log 2>&1
```

> cron 文件要求：`/etc/cron.d/` 下属主 root、权限 644、结尾必须换行。
