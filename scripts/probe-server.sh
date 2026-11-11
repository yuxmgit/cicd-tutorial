#!/usr/bin/env bash
# 服务器只读探测：只读取信息，不安装、不修改、不重启任何东西
# 用法：
#   scp scripts/probe-server.sh yengxun-yun:/tmp/probe.sh
#   ssh yengxun-yun 'bash /tmp/probe.sh'
set -uo pipefail

echo "==================== 1. 系统 ===================="
grep -E "^(PRETTY_NAME|VERSION_ID)=" /etc/os-release
echo "内核: $(uname -r)"
echo "架构: $(uname -m)"
echo "主机: $(hostname)"

echo "==================== 2. CPU / 内存 ===================="
echo "CPU 核数: $(nproc)"
free -h
echo "--- 内存大户 Top5 ---"
ps aux --sort=-rss 2>/dev/null | head -6 | awk '{printf "%-10s %6s %6sMB  %s\n", $1, $3"%", int($6/1024), $11}' || echo "ps 不可用"

echo "==================== 3. 磁盘 ===================="
df -h /
echo "--- inode ---"
df -i / | tail -1

echo "==================== 4. Swap ===================="
if swapon --show | grep -q .; then
  swapon --show
else
  echo "未配置 Swap"
fi

echo "==================== 5. 时间与时区 ===================="
timedatectl 2>/dev/null | head -5 || date

echo "==================== 6. 已装工具 ===================="
for c in docker git curl wget nginx java node npm python3 pip3 make ufw fail2ban-client certbot; do
  printf "%-16s" "$c"
  command -v "$c" >/dev/null 2>&1 && command -v "$c" || echo "NOT INSTALLED"
done

echo "==================== 7. 版本 ===================="
docker --version 2>/dev/null || true
docker compose version 2>/dev/null || true
nginx -v 2>&1 || true
python3 --version 2>/dev/null || true

echo "==================== 8. 监听端口 ===================="
if command -v ss >/dev/null 2>&1; then
  ss -tln | head -20
else
  netstat -tln 2>/dev/null | head -20
fi

echo "==================== 9. 容器 ===================="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null || echo "docker 不可用或无权限"

echo "==================== 10. 防火墙 ===================="
if command -v ufw >/dev/null 2>&1; then
  ufw status 2>/dev/null || echo "ufw 未启用（需 sudo 才能看全）"
else
  echo "未安装 ufw"
fi

echo "==================== 11. 结论 ===================="
avail_mb=$(free -m | awk '/^Mem:/{print $7}')
disk_avail=$(df -h / | awk 'NR==2{print $4}')
echo "可用内存: ${avail_mb} MiB"
echo "根分区可用: ${disk_avail}"
if [ "${avail_mb:-0}" -lt 300 ]; then
  echo "警告：可用内存偏低，部署前先处理内存"
else
  echo "内存余量正常"
fi
