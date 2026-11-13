#!/usr/bin/env bash
# 生产发布脚本：拉镜像 → 建版本目录 → 切软链 → 起容器 → 健康检查 → 失败自动回滚 → 清理旧版本
#
# 用法（在服务器上）：
#   sudo REGISTRY=ghcr.io REGISTRY_NAMESPACE=yxm1989614 \
#        bash scripts/deploy.sh 42-a1b2c3d
#
# 环境变量：
#   APP_BASE_DIR        默认 /opt/apps/cicd-demo
#   KEEP_RELEASES       保留版本数，默认 5
#   HEALTH_URL          默认 http://127.0.0.1:8000/healthz
set -euo pipefail

TAG="${1:?用法: deploy.sh <镜像tag，如 42-a1b2c3d>}"
APP_BASE_DIR="${APP_BASE_DIR:-/opt/apps/cicd-demo}"
REGISTRY="${REGISTRY:?请设置 REGISTRY（镜像仓库域名）}"
NAMESPACE="${REGISTRY_NAMESPACE:?请设置 REGISTRY_NAMESPACE（命名空间）}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8000/healthz}"

RELEASE_ID="$(date +%Y%m%d-%H%M%S)-${TAG}"
RELEASE_DIR="${APP_BASE_DIR}/releases/${RELEASE_ID}"
COMPOSE_SRC="${APP_BASE_DIR}/shared/docker-compose.prod.yml"
CURRENT_LINK="${APP_BASE_DIR}/current"
PREVIOUS=""

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

[ -L "$CURRENT_LINK" ] && PREVIOUS="$(readlink -f "$CURRENT_LINK")"
[ -f "$COMPOSE_SRC" ] || { echo "缺少 $COMPOSE_SRC（请先把 deploy/docker-compose.prod.yml 放到服务器）"; exit 1; }

compose() {
  docker compose -f "${1}/docker-compose.yml" --env-file "${1}/.env" "${@:2}"
}

rollback() {
  if [ -n "$PREVIOUS" ] && [ -d "$PREVIOUS" ]; then
    log "回滚到 $PREVIOUS"
    ln -sfn "$PREVIOUS" "$CURRENT_LINK"
    compose "$PREVIOUS" up -d || true
    log "回滚完成（请检查线上状态）"
  else
    log "没有可回滚的版本，保持现状（首次发布失败？）"
  fi
}

trap 'echo; echo "部署被中断"; rollback; exit 130' INT TERM

log "1/6 准备发布目录：$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp "$COMPOSE_SRC" "${RELEASE_DIR}/docker-compose.yml"
cat > "${RELEASE_DIR}/.env" <<EOF
REGISTRY=${REGISTRY}
NAMESPACE=${NAMESPACE}
IMAGE_TAG=${TAG}
APP_BASE_DIR=${APP_BASE_DIR}
EOF
echo "$TAG" > "${RELEASE_DIR}/VERSION"

log "2/6 拉取镜像"
docker pull "${REGISTRY}/${NAMESPACE}/cicd-demo-backend:${TAG}"
docker pull "${REGISTRY}/${NAMESPACE}/cicd-demo-frontend:${TAG}"

log "3/6 切换 current 并启动"
ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
compose "$RELEASE_DIR" up -d --remove-orphans

log "4/6 健康检查：$HEALTH_URL"
if ! bash "$(dirname "$0")/healthcheck.sh" "$HEALTH_URL" 24 2; then
  log "健康检查失败，输出容器日志"
  compose "$RELEASE_DIR" logs --tail 60 || true
  rollback
  exit 1
fi

log "5/6 记录部署指纹"
docker image inspect "${REGISTRY}/${NAMESPACE}/cicd-demo-backend:${TAG}" \
  --format 'backend digest: {{index .RepoDigests 0}}' | tee "${RELEASE_DIR}/DIGEST" || true

log "6/6 清理旧版本（保留最近 ${KEEP_RELEASES} 个）"
# 按修改时间倒序，跳过当前版本，删除超出的
ls -1dt "${APP_BASE_DIR}"/releases/*/ 2>/dev/null | tail -n +$((KEEP_RELEASES + 1)) | while read -r old; do
  [ "$(readlink -f "$old")" = "$(readlink -f "$CURRENT_LINK")" ] && continue
  echo "  删除旧版本：$old"
  rm -rf "$old"
done

log "部署完成：${TAG}"
echo "当前版本目录：$(readlink -f "$CURRENT_LINK")"
