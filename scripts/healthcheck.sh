#!/usr/bin/env bash
# 重试式健康检查：给应用留够启动时间，避免"刚起来就被判死"
#
# 用法：bash scripts/healthcheck.sh [URL] [重试次数] [间隔秒]
#   bash scripts/healthcheck.sh http://127.0.0.1:8000/healthz 24 2
set -euo pipefail

URL="${1:-http://127.0.0.1:8000/healthz}"
RETRIES="${2:-24}"
INTERVAL="${3:-2}"

echo "健康检查：$URL（最多 ${RETRIES} 次，每次间隔 ${INTERVAL}s）"

for i in $(seq 1 "$RETRIES"); do
  if curl -fsS --max-time 3 "$URL" >/dev/null 2>&1; then
    echo "通过：第 ${i} 次尝试（约 $((i * INTERVAL)) 秒）"
    exit 0
  fi
  printf "  第 %s 次失败，%ss 后重试\n" "$i" "$INTERVAL"
  sleep "$INTERVAL"
done

echo "失败：${RETRIES} 次尝试后仍不可用"
exit 1
