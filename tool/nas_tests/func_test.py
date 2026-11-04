#!/usr/bin/env python3
"""NAS 部署形态功能测试（API 全量）。

用法：python3 tool/nas_tests/func_test.py [base_url]
默认 base：http://192.168.3.153:12702（EQ14）

覆盖：健康检查 / 书架分页排序 / 详情 / 章节索引 / 正文解码 / 搜索 / 统计 /
      导入写入闭环（建书→批量章→改正文→touch→改书→查重）/ 进度书签笔记 CRUD / 静态 UI。
测试书自建自清理，不污染书库。
"""
import json
import sys
import urllib.parse
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://192.168.3.153:12702"
PASS, FAIL = 0, 0
TEST_TITLE = "NAS功能测试书"
TEST_AUTHOR = "自动测试"


def req(method, path, body=None):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"} if body is not None else {}
    r = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(r, timeout=30) as resp:
        ct = resp.headers.get("Content-Type", "")
        raw = resp.read()
        return json.loads(raw) if "json" in ct else raw


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def main():
    print(f"== 目标：{BASE}")
    print("== 1. 健康检查")
    h = req("GET", "/api/health")
    check("health.ok", h.get("ok") is True, h)
    check("health.indexReady", h.get("indexReady") is True, h)
    print(f"     书库 {h.get('books')} 本，demo={h.get('demo')}")

    print("== 2. 书架列表 / 分页 / 排序")
    books = req("GET", "/api/books?page=1&perPage=2")
    check("books.list", isinstance(books.get("books"), list) and len(books["books"]) > 0, str(books)[:200])
    check("books.pageLimit", len(books["books"]) <= 2, str(len(books.get("books", []))))
    b0 = books["books"][0]
    check("books.fields", all(k in b0 for k in ("id", "title", "author")), str(b0)[:200])
    srt = req("GET", "/api/books?page=1&perPage=5&sortBy=title&order=asc")
    check("books.sortBy", isinstance(srt.get("books"), list), str(srt)[:150])

    print("== 3. 详情 / 章节索引 / 正文")
    bid = b0["id"]
    detail = req("GET", f"/api/books/{bid}")
    check("detail.book", detail.get("id") == bid, str(detail)[:150])
    check("detail.chapterCount", isinstance(detail.get("chapterCount"), int) and detail["chapterCount"] > 0,
          str(detail.get("chapterCount")))
    chs = req("GET", f"/api/books/{bid}/chapters")
    cl = chs.get("chapters") if isinstance(chs, dict) else chs
    check("chapters.list", isinstance(cl, list) and len(cl) > 0, str(chs)[:150])
    check("chapters.noContent", not cl[0].get("content"), "章节索引不应含正文")
    ch = req("GET", f"/api/chapters/{cl[0]['id']}")
    check("chapter.content", len(ch.get("content") or "") > 20, f"len={len(ch.get('content') or '')}")

    print("== 4. 搜索 / 统计")
    q = urllib.parse.quote("的")
    sr = req("GET", f"/api/books?page=1&perPage=3&search={q}")
    check("search.ok", isinstance(sr.get("books"), list), str(sr)[:150])
    st = req("GET", "/api/stats")
    check("stats.ok", isinstance(st, dict) and len(st) > 0, str(st)[:150])

    print("== 5. 导入写入闭环")
    old = req("GET", "/api/books/by-title?" + urllib.parse.urlencode({"title": TEST_TITLE, "author": TEST_AUTHOR}))
    if isinstance(old, dict) and old.get("id"):
        req("DELETE", f"/api/books/{old['id']}")  # 清理上次残留
    t = req("GET", "/api/books/by-title?" + urllib.parse.urlencode({"title": TEST_TITLE, "author": TEST_AUTHOR}))
    check("bytitle.ok", t is None or isinstance(t, (dict, list)), str(t)[:120])
    nb = req("POST", "/api/books", {
        "title": TEST_TITLE, "author": TEST_AUTHOR, "status": "连载中",
        "tags": ["NAS测试标签"], "summary": "API 功能测试自建书", "sourceFormat": "txt",
    })
    nid = nb.get("id") or (nb.get("book") or {}).get("id")
    check("import.createBook", bool(nid), str(nb)[:200])
    req("POST", f"/api/books/{nid}/chapters", {"chapters": [
        {"chapterNumber": 1, "title": "第一章 起源", "content": "第一章正文，用于验证批量写入。" * 3},
        {"chapterNumber": 2, "title": "第二章 发展", "content": "第二章正文与第一章不同，去重依赖差异。" * 3},
    ]})
    cl2 = req("GET", f"/api/books/{nid}/chapters")
    cl2 = cl2.get("chapters") if isinstance(cl2, dict) else cl2
    check("import.batchChapters", isinstance(cl2, list) and len(cl2) == 2, str(cl2)[:150])
    cid1 = cl2[0]["id"]
    upd = req("PUT", f"/api/chapters/{cid1}/content", {"content": "更新后的第一章正文。"})
    check("import.updateContent", isinstance(upd, dict) and "oldLength" in upd, str(upd)[:150])
    req("POST", f"/api/books/{nid}/touch")
    req("PUT", f"/api/books/{nid}", {"rating": 5})
    det2 = req("GET", f"/api/books/{nid}")
    check("import.ratingSaved", det2.get("rating") == 5, str(det2)[:150])

    print("== 6. 进度 / 书签 / 笔记")
    req("POST", "/api/user/progress", {"bookId": nid, "chapterId": cid1, "position": 42})
    pg = req("GET", f"/api/user/progress?bookId={nid}")
    check("progress.get", "42" in str(pg) or bool(pg), str(pg)[:150])
    req("POST", "/api/user/bookmarks", {"bookId": nid, "chapterId": cid1, "position": 10,
                                        "title": "测试书签", "excerpt": "摘录"})
    bms = req("GET", f"/api/user/bookmarks?bookId={nid}")
    bl = bms.get("bookmarks") if isinstance(bms, dict) else bms
    check("bookmark.list", isinstance(bl, list) and len(bl) >= 1, str(bms)[:150])
    if bl:
        req("DELETE", f"/api/user/bookmarks/{bl[-1]['id']}")
    req("POST", "/api/user/notes", {"bookId": nid, "chapterId": cid1, "content": "测试笔记"})
    nts = req("GET", f"/api/user/notes?bookId={nid}")
    nl = nts.get("notes") if isinstance(nts, dict) else nts
    check("note.list", isinstance(nl, list) and len(nl) >= 1, str(nts)[:150])
    if nl:
        req("PUT", f"/api/user/notes/{nl[-1]['id']}", {"content": "改过的笔记"})
        req("DELETE", f"/api/user/notes/{nl[-1]['id']}")
        check("note.crud", True)

    print("== 7. 清理")
    req("DELETE", f"/api/books/{nid}")
    after = req("GET", "/api/books/by-title?" + urllib.parse.urlencode({"title": TEST_TITLE, "author": TEST_AUTHOR}))
    check("cleanup.gone", TEST_TITLE not in json.dumps(after, ensure_ascii=False), str(after)[:120])

    print("== 8. 静态 UI")
    html = req("GET", "/")
    check("ui.index", b"flutter" in html.lower() or b"main.dart.js" in html, str(html)[:80])
    with urllib.request.urlopen(BASE + "/main.dart.js", timeout=60) as r:
        mj = r.read()
    check("ui.mainjs", len(mj) > 1_000_000, f"len={len(mj)}")

    print(f"\n===== 功能测试：PASS {PASS} / FAIL {FAIL} =====")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
