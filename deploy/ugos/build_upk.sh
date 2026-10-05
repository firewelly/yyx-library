#!/bin/bash
# 打包 UGOS Pro 应用（upk）—— YYX书库 · 服务端查询架构
#
# 用法（需在有 docker 与 ugcli 的 Linux 打包机上执行，例如 NAS：
#   /home/frie/ugcli/ugcli）：
#
#   deploy/ugos/build_upk.sh --ui <Flutter Web 构建产物目录> [--build 3] [--skip-image]
#
# 参数：
#   --ui <dir>       Flutter Web 产物（默认 $ROOT/build/web）
#   --build <n>      upk 构建号（版本形如 10.0.1.<n>），默认自动 +1
#   --skip-image     复用已有镜像 tar，不重新 docker build
#   --version <v>    产品版本（默认取 project.yaml 的 version）
#
# 产物：deploy/ugos/build/pkgs/upk/yyx-library-<version>.<build>-ugos-amd64.upk
#
# 要点（踩过的坑）：
#   * 镜像必须 `docker save` 出 docker-archive 格式（含 manifest.json）；
#     OCI 布局的 tar 在 UGOS 的 docker 20.10 上 docker load 会失败，
#     表现为「应用中心显示已安装但无容器、无日志」。
#   * --demo-db 为示例书库（四大名著，公版），用户未放置自有书库时兜底。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UGOS="$ROOT/deploy/ugos"
SERVER="$ROOT/deploy/fnos/bin/novel_server.py"

UI_DIR="$ROOT/build/web"
BUILD=""
SKIP_IMAGE=0
VERSION="$(awk -F': *' '/^version:/{print $2}' "$UGOS/project.yaml" | tr -d ' ')"

while [ $# -gt 0 ]; do
  case "$1" in
    --ui) UI_DIR="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --skip-image) SKIP_IMAGE=1; shift ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

IMAGE="novelmgt-app:${VERSION}"
STAGE="$UGOS/build/stage"
IMAGES="$UGOS/rootfs_amd64/images"
IMAGE_TAR="$IMAGES/novelmgt-app-${VERSION}-amd64.tar"

echo "==> 版本 ${VERSION} / 镜像 ${IMAGE}"

# 1. 前置检查
[ -f "$UI_DIR/index.html" ] || {
  echo "错误：缺少 Flutter Web 构建产物（$UI_DIR/index.html）" >&2
  echo "      请先执行：flutter build web --release" >&2
  exit 1
}
[ -f "$SERVER" ] || { echo "错误：缺少服务端 $SERVER" >&2; exit 1; }

# 2. 生成示例书库
echo "==> 生成示例书库"
python3 "$UGOS/make_demo_db.py" "$UGOS/novelmgt-demo.db"

# 3. 组装构建上下文并构建镜像
if [ "$SKIP_IMAGE" -eq 0 ]; then
  echo "==> 构建镜像"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/bin" "$STAGE/demo" "$STAGE/ui"
  cp -R "$UI_DIR/." "$STAGE/ui/"
  cp "$SERVER" "$STAGE/bin/novel_server.py"
  cp "$UGOS/novelmgt-demo.db" "$STAGE/demo/novelmgt-demo.db"
  cp "$UGOS/Dockerfile" "$STAGE/Dockerfile"
  find "$STAGE" -name "._*" -delete 2>/dev/null || true
  find "$STAGE" -name ".DS_Store" -delete 2>/dev/null || true
  docker build --platform linux/amd64 -t "$IMAGE" "$STAGE"
else
  echo "==> 跳过镜像构建（--skip-image）"
fi

# 4. 导出镜像（docker-archive 格式）
echo "==> 导出镜像 -> $IMAGE_TAR"
mkdir -p "$IMAGES"
docker save "$IMAGE" -o "$IMAGE_TAR"
if ! tar tf "$IMAGE_TAR" | grep -q '^manifest.json$'; then
  echo "错误：导出的镜像不是 docker-archive 格式（缺 manifest.json），" >&2
  echo "      UGOS 的 docker 20.10 无法 load，请检查 docker 客户端版本。" >&2
  exit 1
fi
ls -lh "$IMAGE_TAR"

# 5. ugcli 校验并打包
UGCLI="${UGCLI:-ugcli}"
echo "==> ugcli check"
( cd "$UGOS" && "$UGCLI" check )
echo "==> ugcli pack"
if [ -n "$BUILD" ]; then
  ( cd "$UGOS" && "$UGCLI" pack --build "$BUILD" --arch amd64 )
else
  ( cd "$UGOS" && "$UGCLI" pack --arch amd64 )
fi

echo "==> 产物"
ls -lh "$UGOS/build/pkgs/upk/" 2>/dev/null || find "$UGOS/build" -name "*.upk" -exec ls -lh {} \;
