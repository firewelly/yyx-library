#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成「示例书库」novelmgt-demo.db（随包分发的初版图书库）。

用途：Docker/NAS 部署时，若用户尚未放置自己的书库文件，服务端退回此示例库
（--demo-db），使首次安装即可浏览书库、章节、阅读与全文搜索，界面不再空白报错。

内容为**公有领域古籍原文**（四大名著），由 fetch_demo_texts.py 自维基文库抓取，
这里繁体转简体后写入，不含任何现代版权作品。表结构与主库建表保持一致。

用法：
    python3 fetch_demo_texts.py            # 先抓取原文，生成 demo_texts/*.json
    python3 make_demo_db.py [输出路径]      # 默认 ./novelmgt-demo.db
"""

import json
import os
import sqlite3
import sys
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from fetch_demo_texts import WORKS  # noqa: E402

TAG_COLORS = {
    "古典名著": "#8E24AA",
    "神魔": "#5E35B1",
    "历史": "#6D4C41",
    "世情": "#C2185B",
}

SCHEMA = """
CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        author TEXT,
        summary TEXT,
        status TEXT DEFAULT '连载中',
        sourceUrl TEXT,
        coverImage TEXT,
        coverImagePath TEXT,
        rating INTEGER DEFAULT 0,
        notes TEXT,
        wordCount INTEGER DEFAULT 0,
        lastReadAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      , sourceFormat TEXT, filePath TEXT);

CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL,
        chapterNumber INTEGER NOT NULL,
        originalOrder INTEGER,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        sourceUrl TEXT,
        createdAt TEXT NOT NULL, updatedAt TEXT, sourceFormat TEXT,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      );

CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT DEFAULT '#1976D2'
      );

CREATE TABLE book_tags (
        bookId INTEGER NOT NULL,
        tagId INTEGER NOT NULL,
        PRIMARY KEY (bookId, tagId),
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY (tagId) REFERENCES tags(id) ON DELETE CASCADE
      );

CREATE TABLE reading_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL UNIQUE,
        chapterId INTEGER NOT NULL,
        scrollPosition INTEGER DEFAULT 0,
        lastReadAt TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      );

CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL,
        chapterId INTEGER NOT NULL,
        position INTEGER DEFAULT 0,
        title TEXT,
        note TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      );

CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL,
        chapterId INTEGER NOT NULL,
        position INTEGER DEFAULT 0,
        content TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      );

CREATE INDEX idx_books_title ON books(title);
CREATE INDEX idx_books_status ON books(status);
CREATE INDEX idx_books_rating ON books(rating);
CREATE INDEX idx_books_wordcount ON books(wordCount);
CREATE INDEX idx_books_createdat ON books(createdAt);
CREATE INDEX idx_chapters_bookId ON chapters(bookId);
CREATE INDEX idx_book_tags_bookid ON book_tags(bookId);
CREATE INDEX idx_book_tags_tagid ON book_tags(tagId);
CREATE INDEX idx_reading_progress_book ON reading_progress(bookId);
CREATE INDEX idx_bookmarks_book ON bookmarks(bookId);
CREATE INDEX idx_notes_book ON notes(bookId);
CREATE INDEX idx_notes_chapter ON notes(chapterId);
"""


def to_simplified(text):
    """繁体转简体；zhconv 不可用时原样返回（仍可正常阅读）"""
    try:
        from zhconv import convert
        return convert(text, "zh-hans")
    except ImportError:
        return text


def load_work(slug, texts_dir):
    path = os.path.join(texts_dir, "%s.json" % slug)
    if not os.path.isfile(path):
        raise FileNotFoundError(
            "缺少原文缓存 %s，请先运行: python3 fetch_demo_texts.py" % path)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build(path, texts_dir):
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.executescript(SCHEMA)

    tag_ids = {}
    base = datetime(2025, 1, 1, 10, 0, 0)
    total_chars = 0
    total_chapters = 0

    for bi, work in enumerate(WORKS, start=1):
        try:
            data = load_work(work["slug"], texts_dir)
        except FileNotFoundError as e:
            print("  跳过: %s" % e)
            continue
        chapters = data.get("chapters") or []
        if len(chapters) < work["chapters"]:
            print("  跳过（未抓完）: %s %d/%d 章，请重跑 fetch_demo_texts.py"
                  % (work["title"], len(chapters), work["chapters"]))
            continue

        created = base + timedelta(days=bi)
        chars = sum(len(c["text"]) for c in chapters)
        total_chars += chars
        total_chapters += len(chapters)
        con.execute(
            "INSERT INTO books (title, author, summary, status, sourceUrl, coverImage,"
            " coverImagePath, rating, notes, wordCount, lastReadAt, createdAt, updatedAt,"
            " sourceFormat, filePath) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                work["title"], work["author"], work["summary"], "已完结",
                "https://zh.wikisource.org/wiki/%s" % work["page"],
                None, None, 0, None, chars, None,
                created.isoformat(timespec="seconds"),
                created.isoformat(timespec="seconds"),
                "txt", "sample/%s.txt" % work["title"],
            ),
        )
        book_id = con.execute("SELECT last_insert_rowid()").fetchone()[0]
        for tag in work["tags"]:
            if tag not in tag_ids:
                cur = con.execute("INSERT INTO tags (name, color) VALUES (?,?)",
                                  (tag, TAG_COLORS.get(tag, "#1976D2")))
                tag_ids[tag] = cur.lastrowid
            con.execute("INSERT OR IGNORE INTO book_tags (bookId, tagId) VALUES (?,?)",
                        (book_id, tag_ids[tag]))

        stamp = created.isoformat(timespec="seconds")
        rows = []
        for ci, ch in enumerate(chapters, start=1):
            rows.append((
                book_id, ci, ci,
                to_simplified(ch["title"]),
                to_simplified(ch["text"]),
                ("https://zh.wikisource.org/wiki/%s" % ch["page"]) if ch.get("page") else None,
                stamp, stamp, "txt",
            ))
        con.executemany(
            "INSERT INTO chapters (bookId, chapterNumber, originalOrder, title, content,"
            " sourceUrl, createdAt, updatedAt, sourceFormat) VALUES (?,?,?,?,?,?,?,?,?)",
            rows,
        )
        print("  %-6s %-4s %4d 章 / %d 字" % (work["title"], work["author"], len(chapters), chars))

    con.commit()
    books = con.execute("SELECT COUNT(*) FROM books").fetchone()[0]
    chapters = con.execute("SELECT COUNT(*) FROM chapters").fetchone()[0]
    con.close()
    size = os.path.getsize(path)
    print("已生成示例书库: %s" % path)
    print("  共 %d 部 / %d 章 / %d 字 / %.2f MB"
          % (books, chapters, total_chars, size / 1024.0 / 1024.0))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "novelmgt-demo.db")
    build(out, os.path.join(HERE, "demo_texts"))
