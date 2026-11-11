#!/usr/bin/env bash
# 手动回滚：切回上一个（或指定）版本并重启
#
# 用法（服务器上）：
#   sudo bash scripts/rollback.sh                      # 回到上一个版本
#   sudo bash scripts/rollback.sh 20261111-141700-42   # 回到指定版本目录名
#   sudo bash scripts/rollback.sh --list               # 列出可用版本
set -euo pipefail

APP_BASE_DIR="${APP_BASE_DIR:-/opt/apps/cicd-demo}"
RELEASES_DIR="${APP_BASE_DIR}/releases"
CURRENT_LINK="${APP_BASE_DIR}/current"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8000/healthz}"

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

if [ "${1:-}" = "--list" ]; then
  echo "当前版本：$(readlink -f "$CURRENT_LINK" 2>/dev/null || echo 无)"
  echo "可用版本（新→旧）："
  ls -1dt "${RELEASES_DIR}"/*/ 2>/dev/null | while read -r d; do
    mark=""
    [ "$(readlink -f "$d")" = "$(readlink -f "$CURRENT_LINK" 2>/dev/null)" ] && mark=" ← 当前"
    echo "  $(basename "$d")${mark}"
  done
  exit 0
fi

TARGET_ARG="${1:-}"
if [ -z "$TARGET_ARG" ]; then
  TARGET="$(ls -1dt "${RELEASES_DIR}"/*/ 2>/dev/null | while read -r d; do
    [ "$(readlink -f "$d")" = "$(readlink -f "$CURRENT_LINK" 2>/dev/null)" ] && continue
    echo "$d"; break
  done)"
else
  TARGET="${RELEASES_DIR}/${TARGET_ARG}/"
fi

if [ ! -d "$TARGET" ] || [ ! -f "${TARGET}docker-compose.yml" ]; then
  echo "目标版本不存在或不完整：$TARGET"
  exit 1
fi

log "回滚到：$(basename "$TARGET")"
ln -sfn "$(readlink -f "$TARGET")" "$CURRENT_LINK"

docker compose -f "${TARGET}docker-compose.yml" --env-file "${TARGET}.env" up -d --remove-orphans

log "健康检查"
if bash "$(dirname "$0")/healthcheck.sh" "$HEALTH_URL" 15 2; then
  log "回滚完成，当前版本：$(basename "$TARGET")"
else
  echo "回滚后健康检查仍失败，请立即人工介入！"
  docker compose -f "${TARGET}docker-compose.yml" --env-file "${TARGET}.env" logs --tail 80 || true
  exit 1
fi
