#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
novelmgt NAS 静态服务器 + 用户状态 API（fnOS 应用内置）。

- /            → Flutter web 构建产物（ui/ 目录）
- /db/<文件名> → 指定的单文件 SQLite 书库，HTTP Range（206）按需只读
- /api/state/* → 用户状态（进度/书签/笔记）读写，存独立的状态 SQLite
                （--state-db 指定；NAS 部署时按设备本地存放，不按浏览器隔离）

浏览器端书架/正文直读书库文件；阅读状态走这个极小的 JSON API。
仅用标准库，Python 3.6+ 可运行。

用法：
    python3 novel_webserver.py --web-dir <ui目录> --db <novelmgt.db路径> \
        [--state-db <novelmgt_state.db路径>] [--port 12702]
"""

import argparse
import datetime
import hashlib
import html
import json
import os
import re
import secrets
import sqlite3
import sys
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse, parse_qs

RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)$")

STATE_SCHEMA = """
CREATE TABLE IF NOT EXISTS reading_progress (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bookId INTEGER UNIQUE NOT NULL,
  chapterId INTEGER NOT NULL,
  scrollPosition INTEGER DEFAULT 0,
  lastReadAt TEXT,
  createdAt TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS bookmarks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bookId INTEGER NOT NULL,
  chapterId INTEGER NOT NULL,
  position INTEGER DEFAULT 0,
  title TEXT,
  note TEXT,
  createdAt TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bookId INTEGER NOT NULL,
  chapterId INTEGER NOT NULL,
  position INTEGER DEFAULT 0,
  content TEXT NOT NULL DEFAULT '',
  createdAt TEXT NOT NULL,
  updatedAt TEXT
);
CREATE TABLE IF NOT EXISTS app_consent (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  consentAt TEXT NOT NULL,
  clientIp TEXT,
  userAgent TEXT
);
"""


def now_iso():
    return datetime.datetime.now().isoformat(timespec="seconds")


class StateStore(object):
    """用户状态库（独立于只读书库；单进程多线程，每请求独立连接）"""

    def __init__(self, path):
        self.path = path
        con = sqlite3.connect(path)
        con.executescript(STATE_SCHEMA)
        con.commit()
        con.close()

    def _con(self):
        con = sqlite3.connect(self.path)
        con.row_factory = sqlite3.Row
        return con

    @staticmethod
    def _row_to_dict(row):
        return dict(row) if row is not None else None

    # ---- 进度 ----
    def get_progress(self, book_id):
        with self._con() as con:
            if book_id:
                row = con.execute(
                    "SELECT * FROM reading_progress WHERE bookId=?", (book_id,)
                ).fetchone()
                return self._row_to_dict(row)
            rows = con.execute(
                "SELECT * FROM reading_progress ORDER BY lastReadAt DESC"
            ).fetchall()
            return [dict(r) for r in rows]

    def upsert_progress(self, book_id, chapter_id, scroll_position):
        now = now_iso()
        with self._con() as con:
            existing = con.execute(
                "SELECT id, createdAt FROM reading_progress WHERE bookId=?",
                (book_id,),
            ).fetchone()
            if existing:
                con.execute(
                    "UPDATE reading_progress SET chapterId=?, scrollPosition=?,"
                    " lastReadAt=? WHERE bookId=?",
                    (chapter_id, scroll_position, now, book_id),
                )
                created = existing["createdAt"]
            else:
                con.execute(
                    "INSERT INTO reading_progress"
                    " (bookId, chapterId, scrollPosition, lastReadAt, createdAt)"
                    " VALUES (?,?,?,?,?)",
                    (book_id, chapter_id, scroll_position, now, now),
                )
                created = now
            row = con.execute(
                "SELECT * FROM reading_progress WHERE bookId=?", (book_id,)
            ).fetchone()
            row = self._row_to_dict(row)
            row["createdAt"] = created
            return row

    # ---- 书签 ----
    def get_bookmarks(self, book_id):
        with self._con() as con:
            rows = con.execute(
                "SELECT * FROM bookmarks WHERE bookId=? ORDER BY createdAt DESC",
                (book_id,),
            ).fetchall()
            return [dict(r) for r in rows]

    def add_bookmark(self, b):
        now = now_iso()
        with self._con() as con:
            cur = con.execute(
                "INSERT INTO bookmarks"
                " (bookId, chapterId, position, title, note, createdAt)"
                " VALUES (?,?,?,?,?,?)",
                (b.get("bookId"), b.get("chapterId"), b.get("position", 0),
                 b.get("title"), b.get("note"), now),
            )
            row = con.execute(
                "SELECT * FROM bookmarks WHERE id=?", (cur.lastrowid,)
            ).fetchone()
            return self._row_to_dict(row)

    def delete_bookmark(self, bookmark_id):
        with self._con() as con:
            cur = con.execute("DELETE FROM bookmarks WHERE id=?", (bookmark_id,))
            return cur.rowcount > 0

    # ---- 笔记 ----
    def get_notes(self, book_id=None, chapter_id=None):
        with self._con() as con:
            if book_id is not None:
                rows = con.execute(
                    "SELECT * FROM notes WHERE bookId=? ORDER BY createdAt DESC",
                    (book_id,),
                ).fetchall()
            elif chapter_id is not None:
                rows = con.execute(
                    "SELECT * FROM notes WHERE chapterId=? ORDER BY position ASC",
                    (chapter_id,),
                ).fetchall()
            else:
                rows = []
            return [dict(r) for r in rows]

    def add_note(self, n):
        now = now_iso()
        with self._con() as con:
            cur = con.execute(
                "INSERT INTO notes"
                " (bookId, chapterId, position, content, createdAt, updatedAt)"
                " VALUES (?,?,?,?,?,?)",
                (n.get("bookId"), n.get("chapterId"), n.get("position", 0),
                 n.get("content", ""), now, now),
            )
            row = con.execute(
                "SELECT * FROM notes WHERE id=?", (cur.lastrowid,)
            ).fetchone()
            return self._row_to_dict(row)

    def update_note(self, note_id, n):
        now = now_iso()
        with self._con() as con:
            con.execute(
                "UPDATE notes SET content=?, position=?, updatedAt=? WHERE id=?",
                (n.get("content", ""), n.get("position", 0), now, note_id),
            )
            row = con.execute(
                "SELECT * FROM notes WHERE id=?", (note_id,)
            ).fetchone()
            return self._row_to_dict(row)

    def record_consent(self, client_ip, user_agent):
        con = self._con()
        con.execute(
            "INSERT INTO app_consent (consentAt, clientIp, userAgent) VALUES (?, ?, ?)",
            (now_iso(), client_ip, user_agent),
        )
        con.commit()
        con.close()

    def delete_note(self, note_id):
        with self._con() as con:
            cur = con.execute("DELETE FROM notes WHERE id=?", (note_id,))
            return cur.rowcount > 0



# ============================================================
# 安全加固（2026-11-17，绿联安全测试 2 高危 + 1 中危修复）
# - 高危-2 未授权访问：/api/state/* 与 /db/* 需访问口令鉴权（挑战-应答 + HttpOnly Cookie）
# - 高危-1 首次使用：登录后先展示隐私政策并征求同意（同意留痕状态库）
# - 中危-3 隐私政策入口：/privacy 常驻路由 + 登录页/同意页入口
# ============================================================

SHA256_JS = """
"""

def _render_privacy_md(md_text):
    """极简 Markdown 渲染：标题/加粗/链接 + 段落，不做完整解析。"""
    lines = []
    for raw in (md_text or "").splitlines():
        line = html.escape(raw.rstrip())
        if not line.strip():
            lines.append("<br>")
            continue
        line = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", line)
        line = re.sub(r"\*(.+?)\*", r"<i>\1</i>", line)
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            level = min(len(m.group(1)) + 1, 5)
            lines.append("<h%d>%s</h%d>" % (level, m.group(2), level))
        elif line.startswith("- "):
            lines.append("<li>%s</li>" % line[2:])
        else:
            lines.append("<p>%s</p>" % line)
    return "\n".join(lines)

_PAGE_CSS = """
body{font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;background:#f4f6f8;
     margin:0;padding:24px;display:flex;justify-content:center}
.card{background:#fff;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,.08);
      max-width:720px;width:100%;padding:32px;box-sizing:border-box}
h1{font-size:22px;margin:0 0 12px}h2,h3,h4{margin:18px 0 8px}
p,li{line-height:1.7;font-size:14px;color:#333}
.btn{display:inline-block;background:#2f7d5f;color:#fff;border:0;border-radius:8px;
     padding:10px 28px;font-size:15px;cursor:pointer;margin-top:18px}
.btn.secondary{background:#e5e7eb;color:#374151}
input[type=password]{width:100%;box-sizing:border-box;padding:10px;border:1px solid #d1d5db;
     border-radius:8px;font-size:15px;margin:8px 0 4px}
.err{color:#b91c1c;font-size:13px;min-height:18px;margin-top:6px}
a{color:#2f7d5f}
.privacy-body{max-height:52vh;overflow:auto;border:1px solid #e5e7eb;border-radius:8px;padding:16px}
.meta{color:#6b7280;font-size:12px;margin-top:16px}
"""

def _page_skeleton(title, body_html, extra_js=""):
    return ("""<!doctype html>
<html lang=\"zh-CN\"><head><meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>%s</title><style>%s</style></head><body>
<div class=\"card\">%s</div>
<script>%s</script></body></html>""" % (html.escape(title), _PAGE_CSS, body_html, extra_js))

def _login_page():
    body = """
<h1>YYX书库</h1>
<p>本应用已启用访问口令保护，请输入口令后继续。</p>
<form id=\"f\" onsubmit=\"return doLogin()\">
  <input type=\"password\" id=\"pin\" placeholder=\"访问口令\" autofocus autocomplete=\"current-password\">
  <div class=\"err\" id=\"err\"></div>
  <button class=\"btn\" type=\"submit\">进入书库</button>
</form>
<p class=\"meta\">《隐私政策》已生效，可随时
  <a href=\"/privacy\" target=\"_blank\">查看</a>。</p>
<script>
%s
function doLogin(){
  const err = document.getElementById('err');
  err.textContent = '';
  const pin = document.getElementById('pin').value;
  if (!pin) { err.textContent = '请输入口令'; return false; }
  try {
    const xhr1 = new XMLHttpRequest();
    xhr1.open('GET', '/api/pin-challenge', false);
    xhr1.send();
    const c = JSON.parse(xhr1.responseText);
    if (!c.nonce) { err.textContent = c.error || '获取挑战失败'; return false; }
    const ph = sha256utf8(pin);
    const resp = sha256utf8(c.nonce + ph);
    const xhr2 = new XMLHttpRequest();
    xhr2.open('POST', '/api/pin-login', false);
    xhr2.setRequestHeader('Content-Type', 'application/json');
    xhr2.send(JSON.stringify({nonce: c.nonce, response: resp}));
    if (xhr2.status === 200) { location.href = '/'; return false; }
    err.textContent = JSON.parse(xhr2.responseText).error || '口令不对，再试试';
  } catch (e) { err.textContent = '登录失败：' + e; }
  return false;
}
document.getElementById('f').addEventListener('submit', doLogin);
</script>""" % SHA256_JS
    return _page_skeleton("YYX书库 · 访问验证", body)

def _consent_page(privacy_html):
    body = """
<h1>隐私政策与用户同意</h1>
<p>首次使用 YYX书库 前，请阅读以下隐私政策。书库与阅读数据仅保存在本 NAS 与你的浏览器，
不向开发者或任何第三方上传。</p>
<div class=\"privacy-body\">%s</div>
<p class=\"meta\">完整政策亦可随时从本页与登录页的链接访问。</p>
<button class=\"btn\" onclick=\"agree()\">同意并继续</button>
<button class=\"btn secondary\" onclick=\"document.getElementById('decline').style.display='block'\">不同意</button>
<div class=\"err\" id=\"decline\" style=\"display:none\">未同意隐私政策时无法使用本应用。</div>
<script>
async function agree(){
  await fetch('/api/consent', {method:'POST'});
  location.href = '/';
}
</script>""" % privacy_html
    return _page_skeleton("YYX书库 · 隐私政策同意", body)

def _privacy_page(privacy_html):
    body = """
<h1>隐私政策</h1>
<div class=\"privacy-body\">%s</div>
<p class=\"meta\"><a href=\"/\">返回书库</a></p>""" % privacy_html
    return _page_skeleton("YYX书库 · 隐私政策", body)

def _fallback_privacy():
    return ("<p>本应用为本地 NAS 应用：书库文件与阅读数据（进度/书签/笔记）仅存储在本 NAS 与"
            "你的浏览器中，不向开发者或任何第三方上传。</p>")



_SHA256_JS = """
function sha256utf8(s) { return sha256(unescape(encodeURIComponent(s))); }
function sha256(ascii) {
  function rightRotate(value, amount) { return (value >>> amount) | (value << (32 - amount)); }
  var mathPow = Math.pow, maxWord = mathPow(2, 32), lengthProperty = 'length', i, j, result = '';
  var words = [], asciiBitLength = ascii[lengthProperty] * 8;
  var hash = sha256.h = sha256.h || [], k = sha256.k = sha256.k || [];
  var primeCounter = k[lengthProperty];
  var isComposite = {};
  for (var candidate = 2; primeCounter < 64; candidate++) {
    if (!isComposite[candidate]) {
      for (i = 0; i < 313; i += candidate) { isComposite[i] = candidate; }
      hash[primeCounter] = (mathPow(candidate, .5) * maxWord) | 0;
      k[primeCounter++] = (mathPow(candidate, 1 / 3) * maxWord) | 0;
    }
  }
  ascii += '\\x80';
  while (ascii[lengthProperty] % 64 - 56) ascii += '\\x00';
  for (i = 0; i < ascii[lengthProperty]; i++) {
    j = ascii.charCodeAt(i);
    if (j >> 8) return;
    words[i >> 2] |= j << ((3 - i) % 4) * 8;
  }
  words[words[lengthProperty]] = ((asciiBitLength / maxWord) | 0);
  words[words[lengthProperty]] = (asciiBitLength);
  for (j = 0; j < words[lengthProperty];) {
    i = j;
    var w = words.slice(j, j += 16);
    var oldHash = hash;
    hash = hash.slice(0, 8);
    for (i = 0; i < 64; i++) {
      var w15 = w[i - 15], w2 = w[i - 2];
      var a = hash[0], e = hash[4];
      var temp1 = hash[7]
        + (rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25))
        + ((e & hash[5]) ^ ((~e & hash[6])))
        + k[i]
        + (w[i] = (i < 16) ? w[i] : (
          w[i - 16]
          + (rightRotate(w15, 7) ^ rightRotate(w15, 18) ^ (w15 >>> 3))
          + w[i - 7]
          + (rightRotate(w2, 17) ^ rightRotate(w2, 19) ^ (w2 >>> 10))
        ) | 0
        );
      var temp2 = (rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22))
        + ((a & hash[1]) ^ (a & hash[2]) ^ (hash[1] & hash[2]));
      hash = [(temp1 + temp2) | 0].concat(hash);
      hash[4] = (hash[4] + temp1) | 0;
    }
    for (i = 0; i < 8; i++) { hash[i] = (hash[i] + oldHash[i]) | 0; }
  }
  for (i = 0; i < 8; i++) {
    for (j = 3; j + 1; j--) {
      var b = (hash[i] >> (j * 8)) & 255;
      result += ((b < 16) ? 0 : '') + b.toString(16);
    }
  }
  return result;
}
function sha256utf8(s) { return sha256(unescape(encodeURIComponent(s))); }

"""

class NovelHandler(SimpleHTTPRequestHandler):
    db_path = None      # 只读书库（由 main() 注入）
    state = None        # StateStore（main() 注入；None 时 /api/state 返回 503）
    pin_file = None     # 访问口令文件（main() 注入；非空路径且可读时启用鉴权）
    privacy_file = None # 隐私政策 Markdown（/privacy 与同意页内容来源）
    _tokens = {}        # 会话 token -> 过期时间戳
    _nonces = {}        # 一次性挑战 -> 过期时间戳

    # ================= 鉴权与安全页面 =================

    def _load_pin(self):
        try:
            with open(NovelHandler.pin_file, "r", encoding="utf-8") as f:
                return f.read().strip()
        except OSError:
            return ""

    def _pin_on(self):
        return bool(self._load_pin())

    def _cookies(self):
        out = {}
        for part in (self.headers.get("Cookie") or "").split(";"):
            if "=" in part:
                k, _, v = part.strip().partition("=")
                out[k] = v
        return out

    def _authed(self):
        tok = self._cookies().get("novelmgt_token")
        if not tok:
            return False
        exp = NovelHandler._tokens.get(tok)
        if not exp or exp < time.time():
            NovelHandler._tokens.pop(tok, None)
            return False
        return True

    def _consented(self):
        return self._cookies().get("novelmgt_consent") == "1"

    def _require_auth(self):
        """口令未开启 → 放行；已持有有效会话 → 放行；否则 401。"""
        if not self._pin_on() or self._authed():
            return True
        self._send_json({"error": "unauthorized，请先输入访问口令"}, 401)
        return False

    def _send_html(self, body, status=200):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _load_privacy(self):
        try:
            with open(NovelHandler.privacy_file, "r", encoding="utf-8") as f:
                return _render_privacy_md(f.read())
        except OSError:
            return _fallback_privacy()

    def _handle_pin_challenge(self):
        pin = self._load_pin()
        if not pin:
            return self._send_json({"error": "未启用访问口令"}, 404)
        now = time.time()
        for k in [k for k, v in NovelHandler._nonces.items() if v < now]:
            NovelHandler._nonces.pop(k, None)
        nonce = secrets.token_hex(16)
        NovelHandler._nonces[nonce] = now + 60
        return self._send_json({"nonce": nonce})

    def _handle_pin_login(self, body):
        pin = self._load_pin()
        if not pin:
            return self._send_json({"error": "未启用访问口令"}, 404)
        nonce = str(body.get("nonce", ""))
        resp = str(body.get("response", ""))
        now = time.time()
        expected_full = hashlib.sha256((nonce + hashlib.sha256(pin.encode("utf-8")).hexdigest())
                                       .encode("utf-8")).hexdigest()
        exp_nonce = NovelHandler._nonces.pop(nonce, None)
        if not exp_nonce or exp_nonce < now or not secrets.compare_digest(resp, expected_full):
            return self._send_json({"error": "口令不对，再试试"}, 401)
        token = secrets.token_hex(32)
        NovelHandler._tokens[token] = now + 30 * 24 * 3600
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Set-Cookie",
                         "novelmgt_token=%s; Path=/; HttpOnly; SameSite=Strict; Max-Age=%d"
                         % (token, 30 * 24 * 3600))
        self.send_header("Content-Length", "8")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def _handle_consent(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Set-Cookie",
                         "novelmgt_consent=1; Path=/; Max-Age=31536000; SameSite=Lax")
        self.send_header("Content-Length", "8")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')
        if self.state:
            try:
                self.state.record_consent(self.client_address[0],
                                          self.headers.get("User-Agent", ""))
            except Exception as e:  # noqa: BLE001
                sys.stderr.write("[novelmgt] consent 记录失败: %r\n" % (e,))

    # ================= 状态 API =================

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _read_body_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def _handle_state_get(self, path, query):
        st = self.state
        if st is None:
            return self._send_json({"error": "state db not configured"}, 503)
        if path == "/api/state/progress":
            book_id = query.get("bookId", [None])[0]
            return self._send_json(
                {"row": st.get_progress(int(book_id)) if book_id else None,
                 "rows": [] if book_id else st.get_progress(None)})
        if path == "/api/state/bookmarks":
            book_id = query.get("bookId", [None])[0]
            if not book_id:
                return self._send_json({"error": "bookId required"}, 400)
            return self._send_json({"rows": st.get_bookmarks(int(book_id))})
        if path == "/api/state/notes":
            book_id = query.get("bookId", [None])[0]
            chapter_id = query.get("chapterId", [None])[0]
            return self._send_json({"rows": st.get_notes(
                int(book_id) if book_id else None,
                int(chapter_id) if chapter_id else None)})
        return self._send_json({"error": "not found"}, 404)

    def _handle_state_post(self, path):
        st = self.state
        if st is None:
            return self._send_json({"error": "state db not configured"}, 503)
        body = self._read_body_json()
        if path == "/api/state/progress":
            row = st.upsert_progress(int(body["bookId"]),
                                     int(body["chapterId"]),
                                     int(body.get("scrollPosition", 0)))
            return self._send_json({"row": row})
        if path == "/api/state/bookmarks":
            row = st.add_bookmark(body)
            return self._send_json({"row": row})
        if path == "/api/state/bookmarks/delete":
            return self._send_json({"ok": st.delete_bookmark(int(body["id"]))})
        if path == "/api/state/notes":
            row = st.add_note(body)
            return self._send_json({"row": row})
        if path == "/api/state/notes/update":
            row = st.update_note(int(body["id"]), body)
            return self._send_json({"row": row})
        if path == "/api/state/notes/delete":
            return self._send_json({"ok": st.delete_note(int(body["id"]))})
        return self._send_json({"error": "not found"}, 404)

    # ================= 路由 =================

    def _is_db_request(self):
        return self.db_path and self.path.split("?")[0].startswith("/db/")

    def _is_state_api(self):
        return self.path.split("?")[0].startswith("/api/state/")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/health":
            state_ok = 1 if self.state else 0
            return self._send_json({"ok": True, "state": state_ok, "auth": self._pin_on()})
        if path == "/api/pin-challenge":
            return self._handle_pin_challenge()
        if path == "/privacy":
            return self._send_html(_privacy_page(self._load_privacy()))
        if path == "/consent":
            return self._send_html(_consent_page(self._load_privacy()))
        path_only = self.path.split("?")[0]
        # 首次使用：先弹隐私政策同意页（自愿、明确、主动同意——不依赖口令）
        if path_only in ("/", "/index.html") and not self._consented():
            self.send_response(302)
            self.send_header("Location", "/consent")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        # 同意后再输访问口令（口令开启且未登录 → 登录页）
        if path_only in ("/", "/index.html") and self._pin_on() and not self._authed():
            return self._send_html(_login_page())
        if self._is_state_api() or self._is_db_request():
            if not self._require_auth():
                return
            if self._is_state_api():
                return self._handle_state_get(path, parse_qs(urlparse(self.path).query))
            return self._serve_db(include_body=True)
        if path in ("/", "/index.html"):
            if self._pin_on() and not self._authed():
                return self._send_html(_login_page())
            if not self._consented():
                self.send_response(302)
                self.send_header("Location", "/consent")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
        super().do_GET()

    def do_HEAD(self):
        path_only = self.path.split("?")[0]
        # 首次使用：先弹隐私政策同意页（自愿、明确、主动同意——不依赖口令）
        if path_only in ("/", "/index.html") and not self._consented():
            self.send_response(302)
            self.send_header("Location", "/consent")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        # 同意后再输访问口令（口令开启且未登录 → 登录页）
        if path_only in ("/", "/index.html") and self._pin_on() and not self._authed():
            return self._send_html(_login_page())
        if self._is_state_api() or self._is_db_request():
            if not self._require_auth():
                return
            if self._is_state_api():
                return self._handle_state_get(
                    self.path.split("?")[0], parse_qs(urlparse(self.path).query))
            return self._serve_db(include_body=False)
        super().do_HEAD()

    def do_GET_consent(self):  # 占位避免误删（真正处理在 do_GET 尾部）
        pass

    def do_POST(self):
        path = self.path.split("?")[0]
        if path == "/api/pin-login":
            return self._handle_pin_login(self._read_body_json())
        if path == "/api/consent":
            return self._handle_consent()
        if self._is_state_api():
            if not self._require_auth():
                return
            return self._handle_state_post(path)
        self.send_error(405)

    # ================= 只读书库 =================

    def _serve_db(self, include_body):
        name = unquote(self.path.split("?")[0].split("/db/", 1)[1])
        if "/" in name or "\\" in name or not name:
            self.send_error(404)
            return
        if not os.path.isfile(self.db_path):
            self.send_error(404, "db not found")
            return
        size = os.path.getsize(self.db_path)

        rng = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        if rng:
            m = RANGE_RE.match(rng.strip())
            if m:
                if m.group(1):
                    start = int(m.group(1))
                    end = int(m.group(2)) if m.group(2) else size - 1
                elif m.group(2):
                    start = max(0, size - int(m.group(2)))
                status = 206
            else:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % size)
                self.end_headers()
                return
        end = min(end, size - 1)
        length = end - start + 1

        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache")
        if status == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.end_headers()
        if not include_body:
            return
        with open(self.db_path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(1024 * 1024, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (ConnectionAbortedError, BrokenPipeError):
                    return
                remaining -= len(chunk)

    def end_headers(self):
        # 已显式声明 Cache-Control 的响应不重复追加；静态字体分片与带内容哈希的
        # Flutter 资源走 immutable 长缓存（首帧 unicode-range 分片并发请求偶发
        # 失败会造成豆腐块——长缓存 + index.html 预热解决，2026-11-19）。
        buf = getattr(self, "_headers_buffer", None) or []
        has_cc = any(line.lower().startswith(b"cache-control:") for line in buf)
        if not has_cc:
            path = self.path.split("?")[0]
            if path.startswith("/fonts.gstatic.com/") or path.startswith("/assets/"):
                self.send_header("Cache-Control", "public, max-age=31536000, immutable")
            else:
                self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[novelmgt] %s - %s\n" % (self.address_string(), fmt % args))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--web-dir", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--state-db", default=None,
                    help="用户状态库路径（进度/书签/笔记）；缺省时 /api/state 返回 503")
    ap.add_argument("--port", type=int, default=12702)
    ap.add_argument("--pin-file", default="",
                    help="访问口令文件（0600）；非空且可读时启用口令鉴权")
    ap.add_argument("--privacy-file", default="",
                    help="隐私政策 Markdown 路径（/privacy 与同意页内容来源）")
    args = ap.parse_args()

    # WEB_PIN 环境变量迁移：口令不驻留进程环境（写入 0600 文件后清除）
    env_pin = os.environ.get("WEB_PIN", "").strip()
    if env_pin and args.pin_file and not os.path.isfile(args.pin_file):
        with open(args.pin_file, "w", encoding="utf-8") as f:
            f.write(env_pin)
        os.chmod(args.pin_file, 0o600)
        del os.environ["WEB_PIN"]
        sys.stderr.write("[novelmgt] WEB_PIN 已迁出环境 → %s (0600)\n" % args.pin_file)

    if not os.path.isdir(args.web_dir):
        print("web 目录不存在: %s" % args.web_dir)
        return 1
    if not os.path.isfile(args.db):
        print("书库文件不存在: %s" % args.db)
        return 1

    if args.state_db:
        state_dir = os.path.dirname(os.path.abspath(args.state_db))
        if state_dir and not os.path.isdir(state_dir):
            os.makedirs(state_dir, exist_ok=True)
        NovelHandler.state = StateStore(args.state_db)
        sys.stderr.write("[novelmgt] state db: %s\n" % args.state_db)

    handler = partial(NovelHandler, directory=args.web_dir)
    NovelHandler.db_path = os.path.abspath(args.db)
    NovelHandler.pin_file = os.path.abspath(args.pin_file) if args.pin_file else None
    NovelHandler.privacy_file = os.path.abspath(args.privacy_file) if args.privacy_file else None
    if NovelHandler.pin_file and not os.path.isfile(NovelHandler.pin_file):
        sys.stderr.write("[novelmgt] WARNING: 口令文件不存在（%s），鉴权未启用\n"
                         % NovelHandler.pin_file)

    server = ThreadingHTTPServer(("0.0.0.0", args.port), handler)
    sys.stderr.write("[novelmgt] serving %s + %s on :%d\n"
                     % (args.web_dir, args.db, args.port))
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
