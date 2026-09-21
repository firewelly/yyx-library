#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""小说管理系统 · fnOS 版服务端（路线 B 架构）

与「HTTP Range 直读」旧架构的区别：
- 所有查询在服务端完成（书库 SQLite 在 NAS 本地/CIFS 挂载上直接打开），
  彻底解决旧版「搜索章节要全表扫 5GB 文件」导致的 disk I/O error；
- 章节标题索引落在**状态库**（可写）里，重启复用，不碰只读书库；
- 同时提供 /api/* 接口与 Flutter Web 静态资源（同源，客户端自动进入远程模式）。

端点（JSON 字段与客户端模型 fromJson 对齐，与 Dart 版 API 完全一致）：
  GET  /api/health
  GET  /api/books?page&perPage&sortBy&order&tagId&status&minRating&search&variants=a,b
  GET  /api/books/<id>                   （含 tags + chapterCount）
  GET  /api/books/<id>/chapters          （章节索引，不含正文）
  GET  /api/chapters/<id>                （含正文，gzip 由服务端解码）
  GET  /api/tags
  GET  /api/stats
  GET  /api/user/progress?bookId=        POST /api/user/progress
  GET  /api/user/bookmarks?bookId=       POST /api/user/bookmarks   DELETE /api/user/bookmarks/<id>
  GET  /api/user/notes?bookId=           POST /api/user/notes       PUT/DELETE /api/user/notes/<id>
"""

import argparse
import json
import re
import os
import sqlite3
import sys
import threading
import time
import urllib.parse
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ============================================================
# 全局状态
# ============================================================

ARGS = None
_books_lock = threading.Lock()


def _re_match(pattern, s):
    return re.match(pattern, s)


def book_conn():
    """只读打开书库（每次调用新建连接，避免线程共享问题）"""
    con = sqlite3.connect(
        "file:%s?mode=ro" % ARGS.db.replace("?", "%3f"), uri=True, timeout=30
    )
    con.row_factory = sqlite3.Row
    return con


def state_conn():
    con = sqlite3.connect(ARGS.state_db, timeout=30)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    return con


def init_state_db():
    con = state_conn()
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS reading_progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL UNIQUE,
            chapterId INTEGER NOT NULL,
            scrollPosition INTEGER DEFAULT 0,
            lastReadAt TEXT,
            createdAt TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL, chapterId INTEGER NOT NULL,
            position INTEGER DEFAULT 0, title TEXT, note TEXT, createdAt TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL, chapterId INTEGER NOT NULL,
            position INTEGER DEFAULT 0, content TEXT NOT NULL,
            createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chapter_title_index (
            bookId INTEGER NOT NULL, title TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_cti_title ON chapter_title_index(title);
        CREATE INDEX IF NOT EXISTS idx_cti_book ON chapter_title_index(bookId);
        """
    )
    con.commit()
    con.close()


INDEX_READY = False


def build_title_index():
    """后台构建章节标题索引（旧架构搜索失败的根因就在这一步）"""
    global INDEX_READY
    t0 = time.time()
    try:
        with _books_lock:
            bc = book_conn()
            total_books = bc.execute("SELECT COUNT(*) FROM books").fetchone()[0]
            bc.close()
        sc = state_conn()
        have = sc.execute("SELECT COUNT(DISTINCT bookId) FROM chapter_title_index").fetchone()[0]
        if have >= total_books and have > 0:
            INDEX_READY = True
            log("标题索引已存在（%d 本书），跳过构建" % have)
            sc.close()
            return
        sc.execute("DELETE FROM chapter_title_index")
        sc.commit()

        bc = book_conn()
        cur = bc.execute("SELECT bookId, title FROM chapters")
        batch = []
        n = 0
        while True:
            rows = cur.fetchmany(2000)
            if not rows:
                break
            batch.extend((r["bookId"], r["title"] or "") for r in rows)
            n += len(rows)
            if len(batch) >= 20000:
                sc.executemany("INSERT INTO chapter_title_index VALUES (?, ?)", batch)
                sc.commit()
                batch = []
                if n % 100000 < 2000:
                    log("标题索引构建中: %d 行 (%.1fs)" % (n, time.time() - t0))
        if batch:
            sc.executemany("INSERT INTO chapter_title_index VALUES (?, ?)", batch)
            sc.commit()
        bc.close()
        sc.close()
        INDEX_READY = True
        log("标题索引构建完成: %d 条，耗时 %.1fs" % (n, time.time() - t0))
    except Exception as e:  # noqa: BLE001
        log("标题索引构建失败（搜索将不含章节标题命中）: %r" % e)


def log(msg):
    print("[novelmgt %s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


# ============================================================
# 数据访问
# ============================================================


def decode_content(v):
    if v is None:
        return ""
    if isinstance(v, str):
        return v
    b = bytes(v)
    if len(b) >= 2 and b[0] == 0x1F and b[1] == 0x8B:
        return zlib.decompress(b, 16 + zlib.MAX_WBITS).decode("utf-8", "replace")
    return b.decode("utf-8", "replace")


def book_row(con, row):
    m = {k: row[k] for k in row.keys()}
    m.pop("coverImage", None)
    bid = m["id"]
    m["tags"] = [
        dict(r)
        for r in con.execute(
            "SELECT t.id, t.name, t.color FROM tags t "
            "INNER JOIN book_tags bt ON t.id = bt.tagId WHERE bt.bookId=? ORDER BY t.name",
            (bid,),
        )
    ]
    m["chapterCount"] = con.execute(
        "SELECT COUNT(*) FROM chapters WHERE bookId=?", (bid,)
    ).fetchone()[0]
    return m


SORT_WHITELIST = {
    "title": "b.title",
    "wordCount": "b.wordCount",
    "rating": "b.rating",
    "createdAt": "b.createdAt",
    "updatedAt": "b.updatedAt",
    "chapterCount": "(SELECT COUNT(*) FROM chapters c WHERE c.bookId = b.id)",
}


def api_books(q):
    page = max(1, int(q.get("page", ["1"])[0] or 1))
    per_page = min(200, max(1, int(q.get("perPage", ["50"])[0] or 50)))
    sort_by = q.get("sortBy", ["createdAt"])[0]
    order = "ASC" if q.get("order", ["desc"])[0].lower() == "asc" else "DESC"
    where, args = [], []
    status = q.get("status", [None])[0]
    if status and status != "全部状态":
        where.append("b.status = ?")
        args.append(status)
    if q.get("tagId", [None])[0]:
        where.append("b.id IN (SELECT bookId FROM book_tags WHERE tagId = ?)")
        args.append(int(q["tagId"][0]))
    if q.get("minRating", [None])[0] and int(q["minRating"][0]) > 0:
        where.append("b.rating >= ?")
        args.append(int(q["minRating"][0]))

    variants = []
    for v in [q.get("search", [None])[0]] + q.get("variants", [""])[0].split(","):
        v = (v or "").strip()
        if v and v not in variants:
            variants.append(v)

    search_conds = []
    for v in variants:
        like = "%" + v + "%"
        search_conds += ["b.title LIKE ?", "b.author LIKE ?", "b.summary LIKE ?"]
        args += [like, like, like]
    if variants and INDEX_READY:
        try:
            sc = state_conn()
            conds = " OR ".join(["title LIKE ?"] * len(variants))
            ids = [
                r[0]
                for r in sc.execute(
                    "SELECT DISTINCT bookId FROM chapter_title_index WHERE "
                    + conds
                    + " LIMIT 500",
                    tuple("%" + v + "%" for v in variants),
                )
            ]
            sc.close()
            if ids:
                search_conds.append("b.id IN (%s)" % ",".join("?" * len(ids)))
                args += ids
            elif not search_conds:
                return {"books": [], "total": 0, "page": page, "perPage": per_page}
        except Exception as e:  # noqa: BLE001
            log("章节标题检索失败: %r" % e)
    if search_conds:
        where.append("(" + " OR ".join(search_conds) + ")")

    where_sql = ("WHERE " + " AND ".join(where)) if where else ""
    order_by = SORT_WHITELIST.get(sort_by, "b.createdAt")
    con = book_conn()
    total = con.execute(
        "SELECT COUNT(*) FROM books b " + where_sql, args
    ).fetchone()[0]
    rows = con.execute(
        "SELECT b.* FROM books b %s ORDER BY %s %s LIMIT ? OFFSET ?"
        % (where_sql, order_by, order),
        args + [per_page, (page - 1) * per_page],
    ).fetchall()
    books = [book_row(con, r) for r in rows]
    con.close()
    return {"books": books, "total": total, "page": page, "perPage": per_page}


def api_book(bid):
    con = book_conn()
    row = con.execute("SELECT * FROM books WHERE id=?", (bid,)).fetchone()
    if row is None:
        con.close()
        return None
    m = book_row(con, row)
    con.close()
    return m


def api_book_chapters(bid):
    con = book_conn()
    rows = con.execute(
        "SELECT id, bookId, chapterNumber, originalOrder, title, sourceFormat, "
        "createdAt, updatedAt FROM chapters WHERE bookId=? ORDER BY chapterNumber",
        (bid,),
    ).fetchall()
    con.close()
    return {"chapters": [dict(r) for r in rows]}


def api_chapter(cid):
    con = book_conn()
    row = con.execute("SELECT * FROM chapters WHERE id=?", (cid,)).fetchone()
    con.close()
    if row is None:
        return None
    m = dict(row)
    m["content"] = decode_content(m.get("content"))
    return m


def api_tags():
    con = book_conn()
    rows = con.execute(
        "SELECT t.id, t.name, t.color, COUNT(bt.bookId) as bookCount FROM tags t "
        "LEFT JOIN book_tags bt ON t.id = bt.tagId GROUP BY t.id ORDER BY t.name"
    ).fetchall()
    con.close()
    return {"tags": [dict(r) for r in rows]}


def api_stats():
    con = book_conn()
    g = lambda sql, a=(): con.execute(sql, a).fetchone()[0]  # noqa: E731
    total_books = g("SELECT COUNT(*) FROM books")
    total_chapters = g("SELECT COUNT(*) FROM chapters")
    total_words = g("SELECT COALESCE(SUM(wordCount),0) FROM books")
    total_authors = g(
        "SELECT COUNT(DISTINCT author) FROM books WHERE author IS NOT NULL AND author!=''"
    )
    total_tags = g("SELECT COUNT(*) FROM tags")
    status_dist = {
        r[0] or "未知": r[1]
        for r in con.execute("SELECT status, COUNT(*) FROM books GROUP BY status")
    }
    rating_dist = {
        int(r[0]): r[1]
        for r in con.execute("SELECT rating, COUNT(*) FROM books GROUP BY rating")
    }
    top_tags = [
        {"name": r[0], "color": r[1] or "#1976D2", "c": r[2]}
        for r in con.execute(
            "SELECT t.name, t.color, COUNT(bt.bookId) c FROM tags t "
            "LEFT JOIN book_tags bt ON t.id=bt.tagId GROUP BY t.id ORDER BY c DESC LIMIT 10"
        )
    ]
    top_authors = [
        {"name": r[0], "c": r[1]}
        for r in con.execute(
            "SELECT author, COUNT(*) c FROM books WHERE author IS NOT NULL AND author!='' "
            "GROUP BY author ORDER BY c DESC LIMIT 10"
        )
    ]
    recent = []
    for r in con.execute(
        "SELECT b.* FROM reading_progress rp INNER JOIN books b ON b.id=rp.bookId "
        "ORDER BY rp.lastReadAt DESC LIMIT 10"
    ):
        recent.append(book_row(con, r))
    con.close()
    return {
        "totalBooks": total_books,
        "totalChapters": total_chapters,
        "totalWords": total_words,
        "totalAuthors": total_authors,
        "totalTags": total_tags,
        "statusDistribution": status_dist,
        "ratingDistribution": rating_dist,
        "topTags": top_tags,
        "topAuthors": top_authors,
        "recentlyRead": recent,
    }


# ============================================================
# 用户数据（进度/书签/笔记）
# ============================================================


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def user_progress_get(book_id):
    con = state_conn()
    row = con.execute("SELECT * FROM reading_progress WHERE bookId=?", (book_id,)).fetchone()
    con.close()
    return dict(row) if row else None


def user_progress_put(body):
    con = state_conn()
    t = now_iso()
    con.execute(
        "INSERT INTO reading_progress (bookId, chapterId, scrollPosition, lastReadAt, createdAt) "
        "VALUES (?,?,?,?,?) ON CONFLICT(bookId) DO UPDATE SET chapterId=excluded.chapterId, "
        "scrollPosition=excluded.scrollPosition, lastReadAt=excluded.lastReadAt",
        (body["bookId"], body["chapterId"], body.get("scrollPosition", 0), t, t),
    )
    con.commit()
    row = con.execute("SELECT * FROM reading_progress WHERE bookId=?", (body["bookId"],)).fetchone()
    con.close()
    return dict(row)


def user_list(table, book_id):
    con = state_conn()
    rows = con.execute(
        "SELECT * FROM %s WHERE bookId=? ORDER BY id DESC" % table, (book_id,)
    ).fetchall()
    con.close()
    return {"bookmarks" if table == "bookmarks" else "notes": [dict(r) for r in rows]}


def user_insert(table, body, fields):
    con = state_conn()
    t = now_iso()
    vals = [body.get(f) for f in fields]
    cur = con.execute(
        "INSERT INTO %s (%s) VALUES (%s)" % (table, ",".join(fields), ",".join("?" * len(fields))),
        vals,
    )
    con.commit()
    row = con.execute("SELECT * FROM %s WHERE id=?" % table, (cur.lastrowid,)).fetchone()
    con.close()
    return dict(row)


def user_update_note(nid, body):
    con = state_conn()
    con.execute(
        "UPDATE notes SET content=?, updatedAt=? WHERE id=?", (body.get("content"), now_iso(), nid)
    )
    con.commit()
    row = con.execute("SELECT * FROM notes WHERE id=?", (nid,)).fetchone()
    con.close()
    return dict(row) if row else None


def user_delete(table, rid):
    con = state_conn()
    cur = con.execute("DELETE FROM %s WHERE id=?" % table, (rid,))
    con.commit()
    deleted = cur.rowcount > 0
    con.close()
    return {"deleted": deleted}


# ============================================================
# HTTP 层
# ============================================================

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".otf": "font/otf",
    ".ttf": "font/ttf",
    ".bin": "application/octet-stream",
    ".txt": "text/plain; charset=utf-8",
    ".frag": "application/octet-stream",
}


class Handler(BaseHTTPRequestHandler):
    server_version = "novelmgt-fnos/2.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):  # 静默访问日志（fnOS 日志只留关键信息）
        pass

    # ---------- helpers ----------
    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def read_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        return json.loads(self.rfile.read(n).decode("utf-8"))

    def send_static(self, path):
        # 目录穿越防护
        rel = path.lstrip("/") or "index.html"
        full = os.path.normpath(os.path.join(ARGS.web_dir, rel))
        if not full.startswith(os.path.normpath(ARGS.web_dir)):
            self.send_error(403)
            return
        if os.path.isdir(full):
            full = os.path.join(full, "index.html")
        if not os.path.isfile(full):
            # SPA 回退
            full = os.path.join(ARGS.web_dir, "index.html")
            if not os.path.isfile(full):
                self.send_error(404)
                return
        ext = os.path.splitext(full)[1].lower()
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", MIME.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(data)))
        if rel.startswith("assets/") or rel in ("main.dart.js",):
            self.send_header("Cache-Control", "public, max-age=2592000, immutable")
        else:
            self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    # ---------- routing ----------
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path, q = parsed.path, urllib.parse.parse_qs(parsed.query)
        try:
            if path == "/api/health":
                con = book_conn()
                n = con.execute("SELECT COUNT(*) FROM books").fetchone()[0]
                con.close()
                return self.send_json({"ok": True, "books": n, "indexReady": INDEX_READY})
            if path == "/api/books":
                return self.send_json(api_books(q))
            m = _re_match(r"^/api/books/(\d+)$", path)
            if m:
                b = api_book(int(m.group(1)))
                return self.send_json(b) if b else self.send_json({"error": "not found"}, 404)
            m = _re_match(r"^/api/books/(\d+)/chapters$", path)
            if m:
                return self.send_json(api_book_chapters(int(m.group(1))))
            m = _re_match(r"^/api/chapters/(\d+)$", path)
            if m:
                c = api_chapter(int(m.group(1)))
                return self.send_json(c) if c else self.send_json({"error": "not found"}, 404)
            if path == "/api/tags":
                return self.send_json(api_tags())
            if path == "/api/stats":
                return self.send_json(api_stats())
            if path == "/api/user/progress":
                return self.send_json(user_progress_get(int(q.get("bookId", ["0"])[0])))
            if path == "/api/user/bookmarks":
                return self.send_json(user_list("bookmarks", int(q.get("bookId", ["0"])[0])))
            if path == "/api/user/notes":
                return self.send_json(user_list("notes", int(q.get("bookId", ["0"])[0])))
            if path.startswith("/api/"):
                return self.send_json({"error": "unknown endpoint"}, 404)
            return self.send_static(path)
        except Exception as e:  # noqa: BLE001
            log("GET %s 失败: %r" % (path, e))
            return self.send_json({"error": str(e)}, 500)

    def do_HEAD(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.startswith("/api/health"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_error(405)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            body = self.read_body()
            if path == "/api/user/progress":
                return self.send_json(user_progress_put(body))
            if path == "/api/user/bookmarks":
                return self.send_json(
                    user_insert(
                        "bookmarks",
                        body,
                        ["bookId", "chapterId", "position", "title", "note", "createdAt"],
                    )
                )
            if path == "/api/user/notes":
                b = dict(body)
                b.setdefault("createdAt", now_iso())
                return self.send_json(
                    user_insert(
                        "notes", b, ["bookId", "chapterId", "position", "content", "createdAt", "updatedAt"]
                    )
                )
            return self.send_json({"error": "unknown endpoint"}, 404)
        except Exception as e:  # noqa: BLE001
            log("POST %s 失败: %r" % (path, e))
            return self.send_json({"error": str(e)}, 500)

    def do_PUT(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            m = _re_match(r"^/api/user/notes/(\d+)$", path)
            if m:
                n = user_update_note(int(m.group(1)), self.read_body())
                return self.send_json(n) if n else self.send_json({"error": "not found"}, 404)
            return self.send_json({"error": "unknown endpoint"}, 404)
        except Exception as e:  # noqa: BLE001
            return self.send_json({"error": str(e)}, 500)

    def do_DELETE(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            m = _re_match(r"^/api/user/bookmarks/(\d+)$", path)
            if m:
                return self.send_json(user_delete("bookmarks", int(m.group(1))))
            m = _re_match(r"^/api/user/notes/(\d+)$", path)
            if m:
                return self.send_json(user_delete("notes", int(m.group(1))))
            return self.send_json({"error": "unknown endpoint"}, 404)
        except Exception as e:  # noqa: BLE001
            return self.send_json({"error": str(e)}, 500)



def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--web-dir", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--state-db", required=True)
    ap.add_argument("--port", type=int, default=12702)
    ARGS = ap.parse_args()

    if not os.path.isfile(ARGS.db):
        log("警告: 书库文件不存在: %s（服务仍启动，接口会报错）" % ARGS.db)
    init_state_db()
    log("状态库就绪: %s" % ARGS.state_db)

    threading.Thread(target=build_title_index, daemon=True).start()

    srv = ThreadingHTTPServer(("0.0.0.0", ARGS.port), Handler)
    log("novelmgt fnOS 版已启动: http://0.0.0.0:%d (db=%s)" % (ARGS.port, ARGS.db))
    srv.serve_forever()


if __name__ == "__main__":
    main()
