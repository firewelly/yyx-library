#!/bin/bash
# 构建通用 Docker 镜像（在仓库根目录执行）：
#   deploy/docker/build.sh [tag]        # tag 默认 10.0.3
# 依赖：build/web（flutter build web --release 产物）、deploy/fnos/bin/novel_server.py、
#       deploy/ugos/novelmgt-demo.db（示例书库，缺失则跳过）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:-10.0.3}"
STAGE="$ROOT/deploy/docker/rootfs"

[ -f "$ROOT/build/web/index.html" ] || { echo "缺 build/web，先: flutter build web --release" >&2; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE/ui" "$STAGE/bin" "$STAGE/demo"
cp -R "$ROOT/build/web/." "$STAGE/ui/"
cp "$ROOT/deploy/fnos/bin/novel_server.py" "$STAGE/bin/"
chmod +x "$STAGE/bin/novel_server.py"
[ -f "$ROOT/deploy/ugos/novelmgt-demo.db" ] && \
  cp "$ROOT/deploy/ugos/novelmgt-demo.db" "$STAGE/demo/novelmgt-demo.db"
find "$STAGE" -name "._*" -delete 2>/dev/null || true

python3 "$ROOT/tool/patch_web_offline_fonts.py" "$STAGE/ui/main.dart.js"

docker build -t yyx-library:"$TAG" -f "$ROOT/deploy/docker/Dockerfile" "$ROOT"
echo "✅ yyx-library:$TAG"
