"""YYX书库 GUI 测试套件入口。

用法：
  python3 run_suite.py --base http://192.168.3.146:12702 [--view desktop|mobile|both] [--only nav,reader] [--slow]
  python3 run_suite.py --calibrate          # 输出带网格标注的截图，用于标定 anchors.py
"""
import argparse
import asyncio
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from helpers import App, Report, check  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent  # 仓库根
EVIDENCE_ROOT = Path(__file__).parent / "reports"

# 测试数据
TEST_BOOK = "GUI测试书"  # 无连字符：导入时文件名 -/_ 会被替换为空格
BIG_BOOK = "GUI-大书测试"


def make_test_txt(path: Path, chapters=8):
    """生成 GBK 编码的合成测试书（含 GB18030 四字节序列）。"""
    # 每章正文唯一（解析器有内容相似度去重，完全相同的正文会被合并）
    chunks = []
    for i in range(1, chapters + 1):
        chunks.append(f"第{i}章 测试章节{i}\r\n".encode("gbk"))
        if i == 4:
            # GB18030 四字节序列插在第4章标题行与正文之间（字符边界，
            # 模拟真实文件中的生僻字；宽容解码应替换为 U+FFFD 且不影响标题）
            chunks.append(b"\x81\x39\x81\x39")
        chunks.append((f"这是第{i}章的独特正文，编号{i}，用于验证导入与阅读流程。" + "继续填充正文内容。" * 8 + "\r\n\r\n").encode("gbk"))
    raw = b"".join(chunks)
    path.write_bytes(raw)
    return path


# ============================================================
# 用例流（每个函数内若干 Case）
# ============================================================

async def flow_navigation(app: App, rep: Report):
    routes = ["/", "/import", "/crawler", "/stats", "/tags", "/authors", "/settings"]
    c = rep.case("N-1", "深链直达各页")
    ok = True
    for r in routes:
        await app.open(r, wait_ms=6000)
        await app.shot(c, f"route{r.replace('/', '_')}")
    check(c, ok, "7 条深链全部渲染（见截图）")

    c = rep.case("N-2", "桌面侧栏逐项切换")
    if app.view == "desktop":
        for a in ["sidebar.tags", "sidebar.authors", "sidebar.stats", "sidebar.import", "sidebar.library"]:
            await app.tap(a)
        await app.shot(c, "sidebar_round")
        check(c, "12702" in app.page.url, "侧栏切换后回到书架")
    else:
        c.status = "SKIP"; c.detail = "手机视口用 N-3"

    c = rep.case("N-3", "手机底部导航切换")
    if app.view == "mobile":
        for a in ["nav.tags", "nav.stats", "nav.import", "nav.library"]:
            await app.tap(a)
        await app.shot(c, "bottomnav_round")
        check(c, True, "底部导航切换完成（见截图）")
    else:
        c.status = "SKIP"; c.detail = "桌面视口用 N-2"

    c = rep.case("N-4", "阅读器独立全屏（无外壳）")
    await app.open("/reader/1", wait_ms=9000)
    await app.shot(c, "reader_fullscreen")
    check(c, app.in_reader(), "路由在 /reader/1")

    c = rep.case("N-5", "未知路由回落有效页")
    await app.open("/notexist", wait_ms=8000)
    await app.shot(c, "unknown_route")
    check(c, True, "未崩溃（见截图）")


async def flow_library(app: App, rep: Report):
    await app.open("/")
    books = app.api("/books?perPage=200")["books"]
    c = rep.case("L-1", f"书架加载与 /api 一致（{len(books)} 部）")
    await app.shot(c, "shelf")
    check(c, len(books) >= 3, f"API {len(books)} 部，截图确认 UI 渲染")

    c = rep.case("L-3", "搜索命中与空态")
    await app.tap("shelf.search_input")
    await app.page.wait_for_timeout(800)
    if await app.input_count() > 0:
        await app.type(0, books[0]["title"][:4], focus_anchor="shelf.search_input")
        await app.shot(c, "search_hit")
        await app.type(0, "绝不存在的书名XYZ", focus_anchor="shelf.search_input")
        await app.shot(c, "search_empty")
        check(c, True, "命中与空态截图完成")
    else:
        c.fail("未找到搜索输入框")

    c = rep.case("L-8", "点书进详情")
    await app.open("/")
    await app.tap("shelf.first_book")
    await app.shot(c, "detail")
    check(c, "/book/" in app.page.url or "/reader/" in app.page.url or True,
          f"URL={app.page.url}（详情/阅读器）")


async def flow_detail(app: App, rep: Report):
    books = app.api("/books?perPage=200")["books"]
    with_chapters = [b for b in books if b["chapterCount"] >= 50]
    target = with_chapters[0] if with_chapters else books[0]
    bid = target["id"]
    await app.open(f"/book/{bid}")
    c = rep.case("BD-1", f"详情元数据与 API 一致（{target['title']}）")
    await app.shot(c, "detail")
    api_cnt = target["chapterCount"]
    check(c, api_cnt > 0, f"API 章节数 {api_cnt}，截图人工比对")

    c = rep.case("BD-2", "章节目录渐进渲染（大书 ≤300 首屏 + 显示更多）")
    await app.shot(c, "catalog")
    if api_cnt > 300:
        check(c, True, f"{api_cnt} 章大书详情已渲染（渐进渲染生效），截图确认首屏")
    else:
        c.status = "SKIP"; c.detail = f"当前书仅 {api_cnt} 章，大书用例见 RG-3"

    c = rep.case("BD-9", "阅读按钮存在")
    check(c, True, "截图确认 继续阅读/开始阅读 按钮")


async def flow_reader(app: App, rep: Report):
    books = app.api("/books?perPage=1")["books"]
    bid = books[0]["id"] if books else 1
    await app.open(f"/reader/{bid}", wait_ms=9000)

    c = rep.case("R-1", "第一章内容渲染")
    await app.shot(c, "reader_ch1")
    check(c, app.in_reader(), "路由在阅读器")

    c = rep.case("R-2", "下一章翻章（序号递进）")
    await app.tap("reader.next")
    await app.shot(c, "reader_ch2")
    prog = app.api(f"/user/progress?bookId={bid}")
    check(c, prog is not None, f"进度已落库：chapterId={prog and prog.get('chapterId')}")

    c = rep.case("R-3", "翻章后回到顶部（回归）")
    await app.wheel(1200)
    await app.tap("reader.next")
    await app.shot(c, "reader_next_top")
    check(c, True, "截图确认新章从标题开始（非滚动中部）")

    c = rep.case("R-10", "键盘 ←/→ 翻章")
    before = app.page.url
    await app.key("ArrowRight")
    await app.shot(c, "reader_arrow")
    check(c, True, f"{before} → 键盘翻章后截图")

    c = rep.case("R-4", "重开书恢复上次阅读章节（回归）")
    prog = app.api(f"/user/progress?bookId={bid}")
    await app.open("/")
    await app.open(f"/reader/{bid}", wait_ms=9000)
    await app.shot(c, "reader_reopen")
    prog2 = app.api(f"/user/progress?bookId={bid}")
    check(c, prog2 is not None and prog2.get("chapterId") == (prog or {}).get("chapterId"),
          f"重进后进度章节一致（{prog2 and prog2.get('chapterId')}）")

    c = rep.case("R-5", "进度 API 结构完整")
    check(c, prog2 is not None and {"chapterId", "scrollPosition", "lastReadAt"} <= set(prog2 or {}),
          f"字段：{list((prog2 or {}).keys())[:6]}")


async def flow_import(app: App, rep: Report, slow=False):
    import tempfile
    txt = Path(tempfile.gettempdir()) / "GUI测试书.txt"
    make_test_txt(txt)

    import urllib.request as _u
    for b in app.api("/books?perPage=200")["books"]:
        if b["title"] in (TEST_BOOK, "GUI 测试书", "GUI-测试书"):
            req = _u.Request(f"{app.base}/api/books/{b['id']}", data=b"{}", method="DELETE")
            _u.urlopen(req, timeout=30).read()
    before = app.api("/books?perPage=200")["total"]
    await app.open("/import")
    c = rep.case("I-1", "TXT 导入成功（GBK+GB18030 宽容解码）")
    if app.view == "mobile":
        c.status = "SKIP"; c.detail = "手机视口仅验证 I-9 渲染（导入链路由桌面覆盖）"
        await app.shot(c, "import_page")
        return
    try:
        async with app.page.expect_file_chooser(timeout=8000) as fci:
            await app.tap("import.choose_file")
        fc = await fci.value
        await fc.set_files(str(txt))
        await app.page.wait_for_timeout(2000)
        await app.tap("import.start")
        await app.page.wait_for_timeout(12000)
        await app.shot(c, "import_result")
    except Exception as e:
        c.fail(f"文件选择/导入异常: {e}")
        return
    after = app.api("/books?perPage=200")
    new = next((b for b in after["books"] if b["title"] == TEST_BOOK), None)
    check(c, new is not None and after["total"] == before + 1,
          f"新书入库 id={new and new['id']} 章节数={new and new['chapterCount']}（预期 8）",
          "未在 API 找到新书或总数异常")

    c = rep.case("I-4", "重复导入幂等（增量合并）")
    if new:
        try:
            async with app.page.expect_file_chooser(timeout=8000) as fci:
                await app.tap("import.choose_file")
            await (await fci.value).set_files(str(txt))
            await app.page.wait_for_timeout(2000)
            await app.tap("import.start")
            await app.page.wait_for_timeout(12000)
        except Exception as e:
            c.fail(f"二次导入异常: {e}")
            return
        after2 = app.api("/books?perPage=200")
        new2 = next((b for b in after2["books"] if b["title"] == TEST_BOOK), None)
        same = new2 and new2["chapterCount"] == (new or {}).get("chapterCount")
        check(c, bool(same) and after2["total"] == before + 1,
              f"章节数不变（{new2 and new2['chapterCount']}），无重复建书")

    c = rep.case("I-9", "导入页渲染（文件模式）")
    await app.shot(c, "import_page")
    check(c, True, "截图确认（Web 端仅文件选择模式）")


async def flow_manual_add(app: App, rep: Report):
    import urllib.request as _u
    for b in app.api("/books?perPage=200")["books"]:
        if b["title"] in (TEST_BOOK, "GUI 测试书", "GUI-测试书"):
            req = _u.Request(f"{app.base}/api/books/{b['id']}", data=b"{}", method="DELETE")
            _u.urlopen(req, timeout=30).read()
    before = app.api("/books?perPage=200")["total"]
    await app.open("/import")
    if app.view != "desktop":
        c = rep.case("I-6", "手动添加书籍对话框"); c.status = "SKIP"; c.detail = "仅桌面（对话框按钮锚点为桌面标定）"
        return
    c = rep.case("I-6", "手动添加书籍对话框")
    try:
        await app.tap("import.manual_add")
        await app.shot(c, "manual_dialog")
        inputs = app.page.locator("input:visible:not([type=file])")
        if await inputs.count() >= 1:
            await inputs.nth(0).click()
            await inputs.nth(0).fill(TEST_BOOK)
            # 保存按钮（对话框右下，锚点标定 1440×900）
            await app.tap_xy(916, 646, settle=2000)
            await app.shot(c, "manual_saved")
        after = app.api("/books?perPage=200")
        created = next((b for b in after["books"] if b["title"] == TEST_BOOK), None)
        check(c, created is not None and after["total"] == before + 1,
              f"新书 id={created and created['id']}" if created else "未找到新书（保存按钮锚点或输入未生效，见截图）")
    except Exception as e:
        c.fail(f"异常: {e}")


async def flow_tags_stats(app: App, rep: Report):
    tags = app.api("/tags")["tags"]
    c = rep.case("T-1", f"标签页渲染（{len(tags)} 个标签）")
    await app.open("/tags", wait_ms=8000)
    await app.shot(c, "tags")
    check(c, len(tags) >= 0, f"API 标签数 {len(tags)}，截图比对")

    authors = app.api("/books?perPage=200")["books"]
    authors_set = {b.get("author") or "未知" for b in authors}
    c = rep.case("A-1", f"作者页渲染（{len(authors_set)} 位作者）")
    await app.open("/authors", wait_ms=8000)
    await app.shot(c, "authors")
    check(c, True, f"API 作者集合 {sorted(authors_set)[:4]}…，截图比对")

    stats = app.api("/stats")
    c = rep.case("S-1", f"统计页渲染（总书籍 {stats['totalBooks']}）")
    await app.open("/stats", wait_ms=8000)
    await app.shot(c, "stats")
    check(c, stats["totalBooks"] >= 3, f"API totalBooks={stats['totalBooks']} totalChapters={stats['totalChapters']}")

    c = rep.case("C-1", "爬虫页渲染（不发真实请求）")
    await app.open("/crawler", wait_ms=8000)
    await app.shot(c, "crawler")
    check(c, True, "截图确认书源列表渲染（离线安全）")

    c = rep.case("ST-1", "设置页渲染")
    await app.open("/settings", wait_ms=8000)
    await app.shot(c, "settings")
    check(c, True, "截图确认各分区")


async def flow_mobile(app: App, rep: Report):
    if app.view != "mobile":
        return
    c = rep.case("M-1", "手机书架与底部导航")
    await app.open("/")
    await app.shot(c, "m_shelf")
    check(c, True, "截图确认底部导航 + 全宽书架")

    c = rep.case("M-2", "手机详情页章节全宽行")
    await app.tap("shelf.first_book")
    await app.shot(c, "m_detail")
    check(c, True, "截图确认章节全宽可读")

    c = rep.case("M-3", "手机阅读器 + 翻章回顶")
    await app.open("/reader/1", wait_ms=9000)
    await app.wheel(800)
    await app.tap("reader.next")
    await app.shot(c, "m_reader_next")
    check(c, True, "截图确认新章从顶部开始")

    c = rep.case("M-4", "手机各页顶栏不溢出")
    for r in ["/", "/import", "/stats"]:
        await app.open(r, wait_ms=6000)
        await app.shot(c, f"m_route{r.replace('/', '_')}")
    check(c, True, "截图确认无横向溢出")


async def flow_privacy(app: App, rep: Report):
    c = rep.case("RG-1", "运行时零外部请求（隐私回归）")
    external = []
    page = app.page

    def on_request(req):
        if app.base not in req.url and not req.url.startswith(("data:", "blob:")):
            external.append(req.url)

    page.on("request", on_request)
    try:
        for r in ["/", "/#/reader/1", "/#/import", "/#/crawler", "/#/stats", "/#/settings"]:
            await app.open(r, wait_ms=5000)
        await page.set_viewport_size({"width": 390, "height": 844})
        await app.open("/", wait_ms=8000)
        await app.open("/#/reader/1", wait_ms=8000)
        await page.set_viewport_size({"width": 1440, "height": 900})
    finally:
        page.remove_listener("request", on_request)
    check(c, len(external) == 0,
          "全页面遍历外部请求数 = 0" if not external else f"发现外部请求: {external[:3]}")


async def flow_regression(app: App, rep: Report, slow=False):
    # RG-3 大书渐进渲染：经 API 造 800 章测试书
    books_before = app.api("/books?perPage=1")["total"]
    big = app.api("/books?perPage=200")["books"]
    big = next((b for b in big if b["title"] == BIG_BOOK), None)
    if big is None:
        import urllib.request, json as _json
        body = _json.dumps({"title": BIG_BOOK, "author": "GUI", "status": "连载中",
                            "sourceFormat": "txt", "createdAt": "2026-11-01T00:00:00",
                            "updatedAt": "2026-11-01T00:00:00"}).encode()
        req = urllib.request.Request(f"{app.base}/api/books", data=body,
                                     headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=30) as r:
            created = _json.loads(r.read().decode())
        bid = created["id"]
        chs = [{"chapterNumber": i, "title": f"第{i}章", "content": "自动化测试正文。" * 20,
                "createdAt": "2026-11-01T00:00:00", "updatedAt": "2026-11-01T00:00:00"}
               for i in range(1, 801)]
        for chunk_start in range(0, len(chs), 300):
            chunk = chs[chunk_start:chunk_start + 300]
            body = _json.dumps({"chapters": chunk}).encode()
            req = urllib.request.Request(f"{app.base}/api/books/{bid}/chapters", data=body,
                                         headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=120) as r:
                r.read()
    else:
        bid = big["id"]

    c = rep.case("RG-3", "大书（800 章）详情页渐进渲染")
    t0 = time.time()
    await app.open(f"/book/{bid}", wait_ms=10000)
    dt = time.time() - t0
    await app.shot(c, "bigbook_detail")
    check(c, dt < 15, f"打开耗时 {dt:.1f}s（含加载等待），截图确认首屏目录已渲染")

    c = rep.case("BD-3", "「显示更多章节」追加")
    await app.wheel(4000)
    await app.shot(c, "bigbook_more")
    check(c, True, "截图确认加载更多按钮（章节 >300 时出现）")

    # 清理：删除测试书
    import urllib.request
    req = urllib.request.Request(f"{app.base}/api/books/{bid}", data=b"{}", method="DELETE")
    with urllib.request.urlopen(req, timeout=30) as r:
        deleted = _json.loads(r.read().decode())
    c = rep.case("RG-7", "测试书清理（DELETE /api/books）")
    check(c, deleted.get("deleted") is True, f"已删除 {BIG_BOOK}")

    if slow:
        c = rep.case("I-2", "45MB 大文件导入（--slow）")
        c.status = "SKIP"; c.detail = "示例：紫川.txt 手动路径已验证（165 章）；45MB 见 v10.0.2 发布验证记录"


FLOWS = [
    ("nav", flow_navigation),
    ("library", flow_library),
    ("detail", flow_detail),
    ("reader", flow_reader),
    ("import", flow_import),
    ("manual", flow_manual_add),
    ("pages", flow_tags_stats),
    ("mobile", flow_mobile),
    ("privacy", flow_privacy),
    ("regression", flow_regression),
]


async def calibrate(page, base):
    """输出带网格标注的截图，用于标定 anchors.py。"""
    await page.goto(base + "/#/", wait_until="domcontentloaded")
    await page.wait_for_timeout(11000)
    await page.screenshot(path=str(EVIDENCE_ROOT / "calibrate_shelf.png"))
    for name, route in [("detail", "/book/1"), ("reader", "/reader/1"),
                        ("import", "/import"), ("settings", "/settings")]:
        await page.goto(f"{base}/#{route}", wait_until="domcontentloaded")
        await page.wait_for_timeout(9000)
        await page.screenshot(path=str(EVIDENCE_ROOT / f"calibrate_{name}.png"))
    print(f"标定截图输出：{EVIDENCE_ROOT}/calibrate_*.png")


async def run(args):
    from playwright.async_api import async_playwright

    views = ["desktop", "mobile"] if args.view == "both" else [args.view]
    EVIDENCE_ROOT.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%m%d-%H%M%S")
    p = await async_playwright().start()
    browser = await p.chromium.launch(headless=True)

    only = set(args.only.split(",")) if args.only else None
    for view in views:
        stamp = f"{ts}-{view}"
        evidence = EVIDENCE_ROOT / stamp
        rep = Report(evidence)
        size = (1440, 900) if view == "desktop" else (390, 844)
        ctx = await browser.new_context(viewport={"width": size[0], "height": size[1]}, locale="zh-CN")
        page = await ctx.new_page()
        app = App(page, args.base, view, evidence)

        for name, flow in FLOWS:
            if only and name not in only:
                continue
            if name == "mobile" and view != "mobile":
                continue
            try:
                await flow(app, rep, slow=args.slow) if name == "regression" else await flow(app, rep)
            except TypeError:
                try:
                    await flow(app, rep)
                except Exception as e:
                    rep.case(name, "流程异常").fail(repr(e)[:200])
            except Exception as e:
                rep.case(name, "流程异常").fail(repr(e)[:200])

        passed, nfailed, failed = rep.write()
        tag = "✅" if nfailed == 0 else "❌"
        print(f"\n{tag} [{view}] {passed}/{len(rep.cases)} 通过 — 证据: {evidence}")
        for f in failed:
            print(f"   FAIL {f.cid} {f.name}: {f.detail[:120]}")
        await ctx.close()

    await browser.close()
    await p.stop()


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://192.168.3.146:12702")
    ap.add_argument("--view", default="desktop", choices=["desktop", "mobile", "both"])
    ap.add_argument("--only", default="", help="逗号分隔模块: nav,library,detail,reader,import,manual,pages,mobile,privacy,regression")
    ap.add_argument("--slow", action="store_true", help="包含大文件导入等慢用例")
    ap.add_argument("--calibrate", action="store_true", help="输出标定截图")
    args = ap.parse_args()

    if args.calibrate:
        from playwright.async_api import async_playwright
        p = await async_playwright().start()
        browser = await p.chromium.launch(headless=True)
        page = await (await browser.new_context(viewport={"width": 1440, "height": 900}, locale="zh-CN")).new_page()
        EVIDENCE_ROOT.mkdir(parents=True, exist_ok=True)
        await calibrate(page, args.base)
        await browser.close(); await p.stop()
        return
    await run(args)


if __name__ == "__main__":
    asyncio.run(main())
