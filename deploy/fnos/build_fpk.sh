#!/bin/bash
# 打包 fnOS 应用（novelmgt 2.0 · 路线B 架构）
#
# 用法（在仓库根目录执行）：
#   deploy/fnos/build_fpk.sh
# 产物：deploy/fnos/dist/novelmgt-fnos-<version>.fpk
#
# 组成：
#   manifest / ICON*.PNG / config/ / cmd/ / wizard/  —— fnOS 应用框架
#   app.tgz —— 载荷：bin/novel_server.py（路线B 服务端）+ ui/（Flutter Web 构建产物）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FNOS="$ROOT/deploy/fnos"
DIST="$FNOS/dist"
VERSION=$(awk -F'= *' '/^version/{print $2}' "$FNOS/manifest" | tr -d ' ')
OUT="$DIST/novelmgt-fnos-${VERSION}.fpk"

if [ ! -f "$ROOT/build/web/index.html" ]; then
  echo "错误：缺少 Flutter Web 构建产物 build/web，请先执行 flutter build web --release" >&2
  exit 1
fi

rm -rf "$DIST" "$FNOS/app" && mkdir -p "$DIST" "$FNOS/app/bin" "$FNOS/app/ui" "$FNOS/app/demo"

# 载荷：服务端 + 前端 + 示例书库（用户尚未放置自有书库时兜底）
cp "$FNOS/bin/novel_server.py" "$FNOS/app/bin/"
chmod +x "$FNOS/app/bin/novel_server.py"
cp -R "$ROOT/build/web/." "$FNOS/app/ui/"
DEMO_DB="$ROOT/deploy/ugos/novelmgt-demo.db"
if [ -f "$DEMO_DB" ]; then
  cp "$DEMO_DB" "$FNOS/app/demo/novelmgt-demo.db"
  echo "已内置示例书库: $DEMO_DB"
else
  echo "提示：未找到 $DEMO_DB（先运行 deploy/ugos/make_demo_db.py）；本次不内置示例书库" >&2
fi
find "$FNOS/app" -name "._*" -delete 2>/dev/null || true

# app.tgz（fnOS 的载荷包）
tar -C "$FNOS/app" -czf "$DIST/app.tgz" .
rm -rf "$FNOS/app"

# 组装 fpk
tar -C "$FNOS" -czf "$OUT" \
  manifest ICON.PNG ICON_256.PNG cmd config wizard -C "$DIST" app.tgz

rm -f "$DIST/app.tgz"
echo "✅ 生成: $OUT ($(du -h "$OUT" | cut -f1))"
