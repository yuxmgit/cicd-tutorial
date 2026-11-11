#!/usr/bin/env bash
# 安全扫描门禁：依赖漏洞 + 镜像漏洞 + 明文密钥
#
# 用法：
#   bash scripts/security-scan.sh deps            # 扫依赖（前端+后端）
#   bash scripts/security-scan.sh image <镜像名>   # 扫镜像
#   bash scripts/security-scan.sh secrets          # 扫仓库里的明文密钥
#
# 退出码：0 = 通过（可能有 LOW/MEDIUM），1 = 发现 HIGH/CRITICAL
# 环境变量：SEVERITY 默认 HIGH,CRITICAL；SOFT=1 时工具缺失不失败（仅本地用）
set -euo pipefail

MODE="${1:-deps}"
SEVERITY="${SEVERITY:-HIGH,CRITICAL}"
SOFT="${SOFT:-0}"
FAILED=0

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    if [ "$SOFT" = "1" ]; then
      echo "[跳过] 未安装 $1（SOFT=1）"
      return 1
    fi
    echo "[失败] 缺少必要工具：$1"
    echo "安装参考：$2"
    exit 1
  fi
}

scan_deps() {
  echo "=== 前端依赖漏洞（npm audit）==="
  if [ -f demos/frontend/package-lock.json ]; then
    (cd demos/frontend && npm audit --audit-level=high) || FAILED=1
  else
    echo "[跳过] 没有 package-lock.json"
  fi

  echo "=== 后端依赖漏洞（pip-audit）==="
  if need pip-audit "pip install pip-audit"; then
    pip-audit -r demos/backend/requirements.txt --strict || FAILED=1
  fi
}

scan_image() {
  local image="${2:-}"
  if [ -z "$image" ]; then
    echo "用法：bash scripts/security-scan.sh image <镜像名:tag>"
    exit 1
  fi
  if ! need trivy "https://trivy.dev/latest/docs/installation/"; then
    return 0
  fi

  echo "=== 镜像扫描：$image ==="
  # --exit-code 1 表示发现漏洞即返回非 0；--ignore-unfixed 只报有修复方案的
  trivy image --scanners vuln --severity "$SEVERITY" \
      --ignore-unfixed --exit-code 1 --no-progress "$image" || FAILED=1
}

scan_secrets() {
  if ! need gitleaks "https://github.com/gitleaks/gitleaks#installing"; then
    return 0
  fi
  echo "=== 明文密钥扫描 ==="
  # --redact 避免把命中的密钥打印到 CI 日志里
  gitleaks detect --source . --no-git --redact --verbose || FAILED=1
}

case "$MODE" in
  deps)    scan_deps ;;
  image)   scan_image "$@" ;;
  secrets) scan_secrets ;;
  *)
    echo "未知模式：$MODE（可选：deps / image / secrets）"
    exit 1
    ;;
esac

if [ "$FAILED" -ne 0 ]; then
  echo "----------------------------------------"
  echo "安全门禁未通过：存在 $SEVERITY 级别问题"
  echo "处理选择："
  echo "  1) 升级依赖 / 换基础镜像（首选）"
  echo "  2) 确认误报后加入忽略清单，并记录原因与到期时间"
  echo "  3) 紧急发布时走例外流程（需审批留痕）"
  echo "----------------------------------------"
  exit 1
fi

echo "安全门禁通过"
