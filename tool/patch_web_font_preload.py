#!/usr/bin/env python3
"""Flutter Web 产物字体预热补丁：根治首帧 unicode-range 分片竞态豆腐块。

背景（2026-11-19 DX4600 复测发现）：CanvasKit 的回退字体按 Google Fonts
unicode-range 分片模型按需加载（NotoSansSC ~120 个 woff2）。首帧渲染时并发
发起全部分片请求，LAN 上偶发个别分片失败 → 该分片覆盖的字符（如「雪芹罗吴」）
渲染成豆腐块；刷新后命中缓存才恢复。

本补丁两步（幂等，可重复执行）：
  1. 扫描 <ui>/fonts.gstatic.com/ 下全部字体文件，生成 manifest.json 清单；
  2. 改写 <ui>/index.html：注入「分片全部预热（失败重试 ×5，仍有个别失败不
     阻塞）→ 再启动 Flutter」的引导脚本，替换原 flutter_bootstrap.js 直接
     async 加载。

配合服务端对 fonts.gstatic.com/ 与 assets/ 的 immutable 长缓存，预热后
后续加载全部命中本地缓存，不再有网络竞态。

用法：python3 tool/patch_web_font_preload.py <ui 目录>
"""
import json
import os
import re
import sys

MARK = "font-preload-guard"
BOOTSTRAP_RE = re.compile(
    r'<script src="flutter_bootstrap\.js"[^>]*></script>')


PRELOAD_JS = """
<script>
/* %(MARK)s：字体分片预热后再启动 Flutter（tool/patch_web_font_preload.py 注入）。
   首帧 unicode-range 分片并发请求偶发失败 → 豆腐块；全部预热（重试 ×5）
   + 服务端 immutable 缓存根治。清单缺失/预热失败均降级为直接启动，不阻塞。 */
(function () {
  function start() {
    if (window.__flutterBooted) return;
    window.__flutterBooted = true;
    var s = document.createElement('script');
    s.src = 'flutter_bootstrap.js';
    s.async = true;
    document.body.appendChild(s);
  }
  function fetchRetry(url, n) {
    return fetch(url).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.arrayBuffer();
    }).catch(function (e) {
      if (n <= 0) throw e;
      return new Promise(function (res) { setTimeout(res, 250 * (6 - n)); })
        .then(function () { return fetchRetry(url, n - 1); });
    });
  }
  fetch('fonts.gstatic.com/manifest.json')
    .then(function (r) { if (!r.ok) throw new Error('manifest ' + r.status); return r.json(); })
    .then(function (list) {
      if (!list || !list.length) { start(); return; }
      Promise.all(list.map(function (p) {
        return fetchRetry(p, 5).catch(function () { return null; });
      })).then(start);
    })
    .catch(function () { start(); });
  // 兜底：预热异常卡死 15s 后强制启动
  setTimeout(start, 15000);
})();
</script>
""" % {"MARK": MARK}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    ui = sys.argv[1]
    fonts_root = os.path.join(ui, "fonts.gstatic.com")
    index = os.path.join(ui, "index.html")
    if not os.path.isfile(index):
        print(f"[font_preload] 缺少 {index}", file=sys.stderr)
        return 1

    # 1. 生成字体分片清单（相对 ui/ 的正斜杠路径）
    shards = []
    if os.path.isdir(fonts_root):
        for root, _dirs, files in os.walk(fonts_root):
            for name in sorted(files):
                if name.endswith((".woff2", ".woff", ".otf", ".ttf")):
                    rel = os.path.relpath(os.path.join(root, name), ui)
                    shards.append(rel.replace(os.sep, "/"))
        shards.sort()
        with open(os.path.join(fonts_root, "manifest.json"), "w",
                  encoding="utf-8") as f:
            json.dump(shards, f, ensure_ascii=False, indent=0)
        print(f"[font_preload] manifest.json: {len(shards)} 个字体文件")
    else:
        print(f"[font_preload] 无 fonts.gstatic.com 镜像目录，跳过清单生成")

    # 2. 注入预热脚本（幂等）
    with open(index, encoding="utf-8") as f:
        html = f.read()
    if MARK in html:
        print(f"[font_preload] {index}: 已注入，跳过")
        return 0
    m = BOOTSTRAP_RE.search(html)
    if m:
        html = html[:m.start()] + PRELOAD_JS + html[m.end():]
    else:
        # 模板变体：把预热脚本插到 </body> 前（bootstrap 由 window.onFlutterLoaded
        # 之外的同名机制加载时，预热脚本仅做预热，不接管启动）
        html = html.replace("</body>", PRELOAD_JS + "</body>")
    with open(index, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[font_preload] {index}: 预热脚本已注入")
    return 0


if __name__ == "__main__":
    sys.exit(main())
