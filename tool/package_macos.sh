#!/usr/bin/env bash
# macOS 打包脚本（需在 macOS 机器上运行，要求 Xcode + Flutter）
# 产物: dist/novelmgt_flutter-<ver>-macos.zip（解压即用的 .app）
set -euo pipefail
cd "$(dirname "$0")/.."

VER=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
echo "==> flutter build macos --release"
flutter build macos --release

OUT="dist/novelmgt_flutter-${VER}-macos"
mkdir -p "$OUT"
rm -rf "${OUT:?}/novelmgt_flutter.app"
cp -R build/macos/Build/Products/Release/novelmgt_flutter.app "$OUT/"

# zip 需保留符号链接与权限（-y）
rm -f "${OUT}.zip"
(cd "$OUT" && zip -r -y -q "../$(basename "$OUT").zip" novelmgt_flutter.app)
echo "==> 完成: ${OUT}.zip"
echo "    如需 .dmg: hdiutil create -volname NovelMgt -srcfolder $OUT/novelmgt_flutter.app -ov -format UDZO dist/novelmgt_flutter-${VER}.dmg"
