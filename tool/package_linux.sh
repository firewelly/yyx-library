#!/usr/bin/env bash
# Linux 打包脚本（需在 Linux 机器上运行，要求 clang/cmake/ninja + Flutter）
# 产物: dist/novelmgt_flutter-<ver>-linux-x64.tar.gz（解压运行 bundle/novelmgt_flutter）
set -euo pipefail
cd "$(dirname "$0")/.."

VER=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
echo "==> flutter build linux --release"
flutter build linux --release

OUT="dist/novelmgt_flutter-${VER}-linux-x64"
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R build/linux/x64/release/bundle/* "$OUT/"

rm -f "${OUT}.tar.gz"
tar -czf "${OUT}.tar.gz" "$OUT"
echo "==> 完成: ${OUT}.tar.gz（解压后运行 bundle/novelmgt_flutter）"
