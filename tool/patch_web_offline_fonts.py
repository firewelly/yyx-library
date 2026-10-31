#!/usr/bin/env python3
"""Flutter Web 产物离线化补丁：字体回退 CDN → 本地镜像。

Flutter 框架（dart2js 产物 main.dart.js）内置回退字体基址
"https://fonts.gstatic.com/s/"（引擎按需拉取 Noto Sans SC/TC、Color Emoji 等
字体子集）。该常量无构建期开关（fontFallbackBaseUrl 配置在本 loader 版本
不透传），故直接替换产物中的这一处字符串为相对路径 "fonts.gstatic.com/s/"，
配合仓库 web/fonts.gstatic.com/s/ 下的本地字体镜像（SIL OFL 许可）
与 flutter build web --no-web-resources-cdn（canvaskit/字体本地化）实现全离线。

用法：python3 tool/patch_web_offline_fonts.py <ui 目录>/main.dart.js
幂等：已是本地路径时跳过。
"""
import sys

CDN = "https://fonts.gstatic.com/s/"
LOCAL = "fonts.gstatic.com/s/"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        data = f.read()
    n = data.count(CDN)
    if n == 0:
        if LOCAL in data:
            print(f"[patch_web_offline_fonts] {path}: 已是本地路径，跳过")
            return 0
        print(f"[patch_web_offline_fonts] {path}: 未找到 CDN 字符串（Flutter 版本变化？）", file=sys.stderr)
        return 1
    if n != 1:
        print(f"[patch_web_offline_fonts] {path}: 出现 {n} 次，预期 1 次，请人工确认", file=sys.stderr)
        return 1
    with open(path, "w", encoding="utf-8") as f:
        f.write(data.replace(CDN, LOCAL))
    print(f"[patch_web_offline_fonts] {path}: 字体回退基址 → {LOCAL}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
