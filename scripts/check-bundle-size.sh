#!/usr/bin/env bash
# 前端产物体积门禁：超过阈值就让流水线变红。
# 用法：bash scripts/check-bundle-size.sh demos/frontend/dist 200
#   参数1：产物目录
#   参数2：JS 总量上限（KB，未压缩）
set -euo pipefail

DIST_DIR="${1:-dist}"
LIMIT_KB="${2:-200}"

if [ ! -d "$DIST_DIR" ]; then
  echo "产物目录不存在：$DIST_DIR"
  exit 1
fi

total_kb=$(du -sk "$DIST_DIR" | cut -f1)
js_kb=$(find "$DIST_DIR" -type f -name '*.js' -print0 | xargs -0 -r du -k | awk '{s+=$1} END {print s+0}')
css_kb=$(find "$DIST_DIR" -type f -name '*.css' -print0 | xargs -0 -r du -k | awk '{s+=$1} END {print s+0}')

# 估算 gzip 后体积（2M 带宽下这个数字才是用户真实感受）
gzip_kb=0
while IFS= read -r -d '' f; do
  sz=$(gzip -c "$f" | wc -c)
  gzip_kb=$((gzip_kb + sz / 1024))
done < <(find "$DIST_DIR" -type f \( -name '*.js' -o -name '*.css' -o -name '*.html' \) -print0)

echo "----------------------------------------"
echo "产物体积报告：$DIST_DIR"
echo "  总大小      : ${total_kb} KB"
echo "  JS 总量     : ${js_kb} KB（上限 ${LIMIT_KB} KB）"
echo "  CSS 总量    : ${css_kb} KB"
echo "  gzip 后估算 : ${gzip_kb} KB"
echo "----------------------------------------"

if [ "$js_kb" -gt "$LIMIT_KB" ]; then
  echo "门禁失败：JS 体积 ${js_kb}KB 超过上限 ${LIMIT_KB}KB"
  echo "处理建议：按路由拆分、检查是否误打包了整库、开启 tree-shaking"
  exit 1
fi

if [ "$gzip_kb" -gt 500 ]; then
  echo "门禁失败：gzip 后 ${gzip_kb}KB 过大，在 2M 带宽下首屏会很慢"
  exit 1
fi

echo "门禁通过"
