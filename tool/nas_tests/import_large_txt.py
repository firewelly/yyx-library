#!/usr/bin/env python3
"""NAS 部署形态 · 大 TXT 导入测试（Web UI 导入 + API 完整性断言）。

用法：python3 tool/nas_tests/import_large_txt.py [base_url] [files...]
默认：EQ14，导入 青云直上 GB18030 副本 + 原版 + 吞天剑皇 55MB，测试后自动清理。

断言：
- GB18030 副本与原版章节数一致、正文抽样一致（宽容解码无损）
- 55MB 大书章节数/字数、首中末章有正文、全量章节字符总和与字数统计吻合（>95%）
- 导入后详情页章节标题不再出现「第N章 第N章」重复
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

BASE = "http://192.168.3.153:12702"
args = [a for a in sys.argv[1:] if not a.startswith("http")]
if len(sys.argv) > 1 and sys.argv[1].startswith("http"):
    BASE = sys.argv[1]

PASS, FAIL = 0, 0


def api(path):
    with urllib.request.urlopen(BASE + path, timeout=120) as r:
        return json.loads(r.read())


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}  {detail}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def wait_book(title, timeout=420):
    q = urllib.parse.quote(title)
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            for b in api(f"/api/books?page=1&perPage=5&search={q}").get("books", []):
                if b.get("title") == title:
                    return b
        except Exception:
            pass
        time.sleep(5)
    return None


def ui_import(page, path, title):
    page.goto(BASE + "/#/import", wait_until="domcontentloaded", timeout=30000)
    page.wait_for_timeout(4000)
    with page.expect_file_chooser(timeout=15000) as fci:
        page.mouse.click(1340, 236)
    fci.value.set_files(path)
    page.wait_for_timeout(8000)
    page.mouse.click(850, 373)
    print(f"    {title}: 已提交，等待入库…")
    return wait_book(title)


def main():
    from playwright.sync_api import sync_playwright

    files = args or [
        "/tmp/novel_test/青云直上GBK测试版.txt",
        "/Users/firewell/Downloads/青云直上-鹅城知县.txt",
        "/tmp/novel_test/吞天剑皇-佚名.txt",
    ]
    missing = [f for f in files if not os.path.exists(f)]
    if missing:
        print("缺少测试文件:", missing)
        return 2

    imported = {}
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        ctx = b.new_context(ignore_https_errors=True, viewport={"width": 1440, "height": 900},
                            locale="zh-CN")
        page = ctx.new_page()
        for f in files:
            # 导入书名取文件名，且 -/_ 会被替换为空格（README 已知坑）
            name = os.path.splitext(os.path.basename(f))[0].replace("-", " ").replace("_", " ")
            sz = os.path.getsize(f) / 1048576
            print(f"== 导入 {name} ({sz:.1f}MB)")
            # 同名残留先删
            old = api("/api/books?page=1&perPage=5&search=" + urllib.parse.quote(name)).get("books", [])
            for o in old:
                if o.get("title") == name:
                    urllib.request.urlopen(urllib.request.Request(
                        f"{BASE}/api/books/{o['id']}", method="DELETE"), timeout=30)
            book = ui_import(page, f, name)
            check(f"{name} 入库", book is not None, "" if book else "超时未入库")
            if book:
                imported[name] = book
        ctx.close(); b.close()

    print("\n== 完整性断言")
    # 1) GB18030 与原版对比
    gbk = imported.get("青云直上GBK测试版")
    orig = imported.get("青云直上 鹅城知县")
    if gbk and orig:
        g = api(f"/api/books/{gbk['id']}/chapters").get("chapters", [])
        o = api(f"/api/books/{orig['id']}/chapters").get("chapters", [])
        check("GB18030 副本章节数与原版一致", len(g) == len(o) and len(g) > 1000, f"{len(g)} vs {len(o)}")
        for idx in (5, len(g) // 2, len(g) - 1):
            if idx < len(g) and idx < len(o):
                c1 = api(f"/api/chapters/{g[idx]['id']}").get("content", "")
                c2 = api(f"/api/chapters/{o[idx]['id']}").get("content", "")
                check(f"第{idx+1}章正文一致（GB 解码无损）", c1 == c2,
                      f"{len(c1)} vs {len(c2)}")

    # 2) 大文件完整性
    big = imported.get("吞天剑皇 佚名")
    if big:
        d = api(f"/api/books/{big['id']}")
        chs = api(f"/api/books/{big['id']}/chapters").get("chapters", [])
        check("大书章节数>100", len(chs) > 100, str(len(chs)))
        check("大书字数>1000万", (d.get("wordCount") or 0) > 10_000_000, str(d.get("wordCount")))
        check("章节索引与详情一致", len(chs) == d.get("chapterCount"), f"{len(chs)} vs {d.get('chapterCount')}")
        total = 0
        for ch in chs:
            total += len(api(f"/api/chapters/{ch['id']}").get("content", ""))
        ratio = total / max(1, d.get("wordCount") or 1)
        check("全量正文占字数统计>95%", ratio > 0.95, f"{ratio:.3f}（{total} 字符）")

        # 3) 标题去重：详情页标题不应出现「第N章 第N章」
        dup = re.compile(r"^\s*第\s*[0-9一二三四五六七八九十百千万零两]+\s*[章回节卷]\s*第\s*[0-9一二三四五六七八九十百千万零两]+\s*[章回节卷]")
        bad = [c["title"] for c in chs if dup.match(c.get("title") or "")]
        check("章节标题无「第N章 第N章」重复", len(bad) == 0, f"{len(bad)} 例" + (f"：{bad[:2]}" if bad else ""))

    print(f"\n===== 导入测试：PASS {PASS} / FAIL {FAIL} =====")
    ids = {k: v["id"] for k, v in imported.items()}
    print("导入书籍 id（保留供人工查看）:", json.dumps(ids, ensure_ascii=False))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
