#!/usr/bin/env bash
# 用途：一眼看清这台机器的家底；只读，不做任何修改（第 00 章）
set -euo pipefail

echo "===== 我是谁 ====="
echo "用户: $(whoami)    主机: $(hostname)    时间: $(date '+%F %T %Z')"

echo "===== 系统 ====="
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release

echo "===== 资源 ====="
echo "CPU 核数: $(nproc)"
free -h | awk 'NR<=2'
df -h / | awk 'NR<=2'

echo "===== 端口占用（前 10 个）====="
ss -tlnp 2>/dev/null | head -11

echo "===== 结论 ====="
avail_mb=$(free -m | awk '/^Mem:/{print $7}')
if [ "$avail_mb" -lt 200 ]; then
  echo "警告：可用内存仅 ${avail_mb}MiB，随时可能 OOM，请先腾内存"
else
  echo "可用内存 ${avail_mb}MiB，可以继续"
fi
