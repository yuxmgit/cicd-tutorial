#!/usr/bin/env bash
# 构建镜像 + 体积门禁 +（可选）推送
#
# 用法：
#   bash scripts/build-and-push.sh backend 42
#   PUSH=1 bash scripts/build-and-push.sh frontend 42
#
# 必填环境变量：
#   REGISTRY_NAMESPACE   镜像仓库命名空间
# 可选：
#   REGISTRY             默认 ghcr.io
#   MAX_SIZE_MB          体积上限，默认 250
#   PUSH=1               构建完成后推送（需要已 docker login）
set -euo pipefail

APP="${1:?用法: build-and-push.sh <frontend|backend> <tag>}"
TAG="${2:?缺少 tag，建议用 BUILD_NUMBER 或 git sha}"
REGISTRY="${REGISTRY:-ghcr.io}"
NAMESPACE="${REGISTRY_NAMESPACE:?请设置 REGISTRY_NAMESPACE}"
MAX_SIZE_MB="${MAX_SIZE_MB:-250}"

case "$APP" in
  frontend)
    CONTEXT="demos/frontend"
    DOCKERFILE="deploy/Dockerfile.frontend"
    ;;
  backend)
    CONTEXT="demos/backend"
    DOCKERFILE="deploy/Dockerfile.backend"
    ;;
  *)
    echo "未知应用：$APP（只支持 frontend / backend）"
    exit 1
    ;;
esac

IMAGE="${REGISTRY}/${NAMESPACE}/cicd-demo-${APP}:${TAG}"

echo "=== 构建 ${IMAGE} ==="
echo "上下文：${CONTEXT}   Dockerfile：${DOCKERFILE}"

# 使用 BuildKit：并行构建 + 更好的缓存
DOCKER_BUILDKIT=1 docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  -f "$DOCKERFILE" \
  -t "$IMAGE" \
  "$CONTEXT"

SIZE_BYTES=$(docker image inspect "$IMAGE" --format '{{.Size}}')
SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
IMAGE_ID=$(docker image inspect "$IMAGE" --format '{{.Id}}')

echo "----------------------------------------"
echo "镜像   : ${IMAGE}"
echo "大小   : ${SIZE_MB} MB（上限 ${MAX_SIZE_MB} MB）"
echo "镜像ID : ${IMAGE_ID}"
echo "----------------------------------------"

if [ "$SIZE_MB" -gt "$MAX_SIZE_MB" ]; then
  echo "体积门禁失败：${SIZE_MB}MB > ${MAX_SIZE_MB}MB"
  echo "排查：docker history ${IMAGE} --no-trunc | head -20"
  exit 1
fi

if [ "${PUSH:-0}" = "1" ]; then
  echo "=== 推送 ==="
  docker push "$IMAGE"
  echo "=== 远端 digest ==="
  docker image inspect "$IMAGE" --format '{{index .RepoDigests 0}}' || true
fi

echo "完成"
