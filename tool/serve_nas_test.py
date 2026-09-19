#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NAS 部署本地验证服务器。

模拟 nginx 对 Flutter web 静态目录 + 单文件 SQLite 库的托管行为：
- /            → Flutter web 构建产物（novelmgt_flutter/build/web）
- /db/<文件名> → 指定的 .db 文件，支持 HTTP Range（206 Partial Content）

用法：
    python3 tool/serve_nas_test.py [--web-dir build/web] [--db <db路径>] [--port 8091]

浏览器访问 http://localhost:8091/?nas=1 即可验证 NAS 只读直连模式；
访问 http://localhost:8091/ 验证普通 Web 模式回归。
"""

import argparse
import os
import re
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)$")


class NasTestHandler(SimpleHTTPRequestHandler):
    db_path = None

    def do_GET(self):
        if self.db_path and self.path.split("?")[0].startswith("/db/"):
            self._serve_db(include_body=True)
        else:
            super().do_GET()

    def do_HEAD(self):
        if self.db_path and self.path.split("?")[0].startswith("/db/"):
            self._serve_db(include_body=False)
        else:
            super().do_HEAD()

    def _serve_db(self, include_body):
        name = unquote(self.path.split("?")[0].split("/db/", 1)[1])
        if "/" in name or "\\" in name or not name:
            self.send_error(404)
            return
        path = os.path.join(os.path.dirname(self.db_path), name)
        if not os.path.isfile(path):
            self.send_error(404, "db not found")
            return
        size = os.path.getsize(path)

        rng = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        if rng:
            m = RANGE_RE.match(rng.strip())
            if m:
                if m.group(1):
                    start = int(m.group(1))
                    end = int(m.group(2)) if m.group(2) else size - 1
                elif m.group(2):  # suffix range
                    start = max(0, size - int(m.group(2)))
                status = 206
            else:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
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
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if not include_body:
            return
        with open(path, "rb") as f:
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
        # wasm MIME 由 SimpleHTTPRequestHandler 按扩展名处理；
        # 这里补上禁止缓存 index.html，避免更新后浏览器用旧产物
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[nas-test] %s - %s\n" % (self.address_string(), fmt % args))


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    default_web = os.path.normpath(os.path.join(here, "..", "build", "web"))
    default_db = os.path.join(
        os.environ.get("APPDATA", ""), "com.example", "novelmgt_flutter", "novelmgt.db"
    )
    ap.add_argument("--web-dir", default=default_web)
    ap.add_argument("--db", default=default_db, help="映射到 /db/ 下的 .db 文件")
    ap.add_argument("--port", type=int, default=8091)
    args = ap.parse_args()

    if not os.path.isdir(args.web_dir):
        print(f"web 目录不存在: {args.web_dir}")
        return 1
    if not os.path.isfile(args.db):
        print(f"db 文件不存在: {args.db}")
        return 1

    handler = partial(NasTestHandler, directory=args.web_dir)
    NasTestHandler.db_path = os.path.abspath(args.db)

    server = ThreadingHTTPServer(("0.0.0.0", args.port), handler)
    print(f"web dir : {args.web_dir}")
    print(f"db      : {args.db}  ->  /db/{os.path.basename(args.db)}")
    print(f"NAS 模式: http://localhost:{args.port}/?nas=1")
    print(f"普通模式: http://localhost:{args.port}/")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
