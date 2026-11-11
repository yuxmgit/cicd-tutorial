#!/usr/bin/env bash
# 生产服务器初始化（幂等，可重复执行）
#
# 用法：
#   sudo bash scripts/init-server.sh              # 标准初始化（不动 SSH 配置）
#   sudo bash scripts/init-server.sh --dry-run    # 只打印要做什么
#   sudo bash scripts/init-server.sh --skip-ufw   # 不启用 ufw（安全组已够用时）
#   sudo bash scripts/init-server.sh --harden-ssh # 禁用密码登录（危险，先看文档第 11 章）
#
# 设计原则：
# 1. 幂等：每一步都先检查，已完成的跳过。
# 2. 不碰不可逆的东西：SSH 加固必须显式开启。
# 3. 每步都有验证输出，失败即退出。
set -euo pipefail

DRY_RUN=0
ENABLE_UFW=1
HARDEN_SSH=0
APP_BASE_DIR="${APP_BASE_DIR:-/opt/apps/cicd-demo}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-ufw)   ENABLE_UFW=0 ;;
    --harden-ssh) HARDEN_SSH=1 ;;
    *) echo "未知参数：$arg"; exit 1 ;;
  esac
done

log()  { echo; echo "==================== $* ===================="; }
run()  {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}
need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行：sudo bash $0 $*"
    exit 1
  fi
}
has() { command -v "$1" >/dev/null 2>&1; }

need_root "$@"

log "0. 环境确认"
grep -E "^(PRETTY_NAME|VERSION_ID)=" /etc/os-release
echo "内核: $(uname -r)   CPU: $(nproc) 核"
free -h | head -2
df -h / | tail -1

log "1. 更新软件包索引并安装基础工具"
run "apt-get update -y"
run "DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release ufw fail2ban unzip jq"

log "2. 安装 Docker（官方仓库，失败则回退系统包）"
if has docker; then
  echo "已安装：$(docker --version)，跳过"
else
  CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
  echo "系统代号：${CODENAME}"
  run "install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
  run "chmod a+r /etc/apt/keyrings/docker.asc"
  run "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list"

  if run "apt-get update -y" && run "DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"; then
    echo "Docker 官方仓库安装成功"
  else
    echo "官方仓库安装失败（可能是新系统暂无对应源），回退到 Ubuntu 自带 docker.io"
    run "rm -f /etc/apt/sources.list.d/docker.list"
    run "apt-get update -y"
    run "DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2"
  fi
fi

log "3. 配置 Docker：日志轮转 + 镜像加速"
DAEMON_JSON=/etc/docker/daemon.json
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] 写入 $DAEMON_JSON（日志轮转 10m×3 + 腾讯云内网镜像加速）"
elif [ ! -f "$DAEMON_JSON" ]; then
  mkdir -p /etc/docker
  cat > "$DAEMON_JSON" <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com"
  ]
}
JSON
  echo "已写入 $DAEMON_JSON"
else
  echo "$DAEMON_JSON 已存在，未覆盖。当前内容："
  cat "$DAEMON_JSON"
fi

run "systemctl enable --now docker"
run "systemctl restart docker"

log "4. 安装并启用 Nginx"
if has nginx; then
  echo "已安装：$(nginx -v 2>&1)，跳过"
else
  run "DEBIAN_FRONTEND=noninteractive apt-get install -y nginx"
fi
run "systemctl enable --now nginx"

log "5. 创建部署目录规范"
# releases 放各版本产物，shared 放跨版本共享数据，current 指向当前版本（软链接）
run "mkdir -p ${APP_BASE_DIR}/{releases,shared/data,shared/logs}"
run "chown -R ${SUDO_USER:-ubuntu}:${SUDO_USER:-ubuntu} ${APP_BASE_DIR}"
if [ ! -L "${APP_BASE_DIR}/current" ]; then
  run "ln -sfn ${APP_BASE_DIR}/releases ${APP_BASE_DIR}/current"
fi
echo "目录结构："
ls -la "${APP_BASE_DIR}" 2>/dev/null || true

log "6. 配置 ufw（先放通 SSH，再启用，顺序不能错）"
if [ "$ENABLE_UFW" -eq 1 ]; then
  run "ufw allow OpenSSH"
  run "ufw allow 80/tcp"
  run "ufw allow 443/tcp"
  run "ufw --force enable"
  run "ufw status verbose"
else
  echo "按参数跳过 ufw"
fi

log "7. 配置 fail2ban 保护 SSH"
if [ -f /etc/fail2ban/jail.local ]; then
  echo "/etc/fail2ban/jail.local 已存在，未覆盖"
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] 写入 /etc/fail2ban/jail.local"
else
  cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
JAIL
  echo "已写入 /etc/fail2ban/jail.local"
fi
run "systemctl enable --now fail2ban"

log "8. SSH 加固（仅 --harden-ssh 时执行）"
if [ "$HARDEN_SSH" -eq 1 ]; then
  echo "警告：禁用密码登录后，只能用密钥登录。请确认另一个终端能免密登录再继续。"
  run "sed -ri 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config"
  run "sed -ri 's/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config"
  run "sshd -t"
  run "systemctl reload ssh"
  echo "已加固。务必保持当前会话不要断，另开终端验证能登录后再关。"
else
  echo "跳过（加 --harden-ssh 才会改 SSH 配置）"
fi

log "9. 结果验证"
echo "Docker : $(docker --version 2>/dev/null || echo 未安装)"
echo "Compose: $(docker compose version 2>/dev/null || echo 未安装)"
echo "Nginx  : $(nginx -v 2>&1 || echo 未安装)"
echo "ufw    : $(ufw status 2>/dev/null | head -1 || echo 未启用)"
echo "SSH 密码登录: $(sshd -T 2>/dev/null | grep -i '^passwordauthentication' || echo 未知)"
echo "磁盘   : $(df -h / | tail -1)"
echo "内存   : $(free -h | sed -n '2p')"

log "完成"
echo "下一步：把 80/443 加入腾讯云安全组入站规则（控制台操作），然后进入第 12 章。"
