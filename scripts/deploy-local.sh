#!/usr/bin/env bash
# 本地镜像部署（无镜像仓库路径）：镜像已由 Jenkins docker load 进本机
# 用法：TAG=42-a1b2c3d LOCAL_DEPLOY=1 bash -s < scripts/deploy-local.sh   （经 SSH 执行）
set -euo pipefail

TAG="${TAG:?缺少 TAG 环境变量}"
APP_BASE_DIR="${APP_BASE_DIR:-/opt/apps/cicd-demo}"
RELEASE_ID="$(date +%Y%m%d-%H%M%S)-${TAG}"
RELEASE_DIR="${APP_BASE_DIR}/releases/${RELEASE_ID}"
CURRENT_LINK="${APP_BASE_DIR}/current"
PREVIOUS=""

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

[ -L "$CURRENT_LINK" ] && PREVIOUS="$(readlink -f "$CURRENT_LINK")"

rollback() {
  if [ -n "$PREVIOUS" ] && [ -d "$PREVIOUS" ]; then
    log "回滚到 $PREVIOUS"
    ln -sfn "$PREVIOUS" "$CURRENT_LINK"
    docker compose -f "$PREVIOUS/docker-compose.yml" --env-file "$PREVIOUS/.env" up -d || true
  fi
}

trap 'echo 部署被中断; rollback; exit 130' INT TERM

log "1/4 准备发布目录 $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 本地镜像版 compose：image 直接用本机 tag，不需要 REGISTRY/NAMESPACE
cat > "${RELEASE_DIR}/docker-compose.yml" <<EOF
name: cicd-demo

services:
  api:
    image: cicd-demo-backend:${TAG}
    restart: unless-stopped
    ports:
      - "127.0.0.1:8000:8000"
    environment:
      SQLITE_PATH: /data/app.db
      APP_VERSION: ${TAG}
    volumes:
      - ${APP_BASE_DIR}/shared/data:/data
    stop_grace_period: 30s
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }

  web:
    image: cicd-demo-frontend:${TAG}
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${APP_BASE_DIR}/shared/nginx/site.conf:/etc/nginx/conf.d/default.conf:ro
      - ${APP_BASE_DIR}/shared/certs:/etc/nginx/certs:ro
    depends_on:
      - api
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "3" }
EOF

echo "$TAG" > "${RELEASE_DIR}/VERSION"
sudo chown -R ubuntu:ubuntu "${APP_BASE_DIR}/releases" 2>/dev/null || true

log "2/4 切换 current 并启动"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
docker compose -f "${RELEASE_DIR}/docker-compose.yml" --env-file /dev/null up -d --remove-orphans

log "3/4 健康检查"
if ! curl -fsS --max-time 3 http://127.0.0.1:8000/healthz >/dev/null 2>&1; then
  for i in $(seq 1 24); do
    curl -fsS --max-time 3 http://127.0.0.1:8000/healthz >/dev/null 2>&1 && { ok=1; break; }
    sleep 2
  done
  if [ "${ok:-0}" -ne 1 ]; then
    log "健康检查失败，输出日志"
    docker compose -f "${RELEASE_DIR}/docker-compose.yml" logs --tail 60 || true
    rollback
    exit 1
  fi
fi
log "健康检查通过"

log "4/4 清理旧版本（保留最近 5 个）"
ls -1dt "${APP_BASE_DIR}"/releases/*/ 2>/dev/null | tail -n +6 | while read -r old; do
  [ "$(readlink -f "$old")" = "$(readlink -f "$CURRENT_LINK")" ] && continue
  echo "  删除 $old"; rm -rf "$old"
done

log "部署完成：${TAG}（本地镜像路径）"
