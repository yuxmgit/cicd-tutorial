#!/usr/bin/env bash
# 服务器清理：镜像、构建缓存、容器日志（防止 40G 系统盘被吃满）
#
# 用法（服务器上）：
#   sudo bash scripts/cleanup.sh            # 常规清理
#   sudo bash scripts/cleanup.sh --aggressive  # 深度清理（连未使用镜像一起删）
#
# 建议加入 cron：每周日凌晨执行
set -euo pipefail

AGGRESSIVE=0
[ "${1:-}" = "--aggressive" ] && AGGRESSIVE=1

log() { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
BEFORE=$(df -h / | awk 'NR==2{print $3}')

log "1/4 清理悬空镜像与停止的容器"
docker container prune -f
docker image prune -f

if [ "$AGGRESSIVE" -eq 1 ]; then
  log "深度清理：删除所有未被容器引用的镜像"
  docker image prune -af
  log "清理 7 天前的构建缓存"
  docker builder prune -af --filter until=168h
fi

log "2/4 按保留数量清理应用旧镜像（保留最近 5 个 tag）"
for repo in cicd-demo-backend cicd-demo-frontend; do
  docker images --format '{{.Repository}}:{{.Tag}}' \
    | grep "^.*${repo}:" | grep -v '<none>' | sort -r | tail -n +6 \
    | while read -r img; do
        log "  删除旧镜像 $img"
        docker rmi "$img" 2>/dev/null || true
      done
done

log "3/4 截断超过 100MB 的容器日志"
# daemon.json 已限制 10m×3，这里兜底处理历史遗留的大日志
find /var/lib/docker/containers -name '*-json.log' -type f -size +100M -print -exec truncate -s 0 {} \; 2>/dev/null || true

log "4/4 结果"
docker system df
AFTER=$(df -h / | awk 'NR==2{print $3}')
log "磁盘占用：清理前 ${BEFORE} → 清理后 ${AFTER}"
