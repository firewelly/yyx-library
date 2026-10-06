#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将 novelmgt.db 的章节正文迁移为 gzip 压缩存储（BLOB）。

格式与 lib/utils/content_codec.dart（ContentCodec）及
deploy/fnos/bin/novel_server.py 的 decode_content() 完全一致：
gzip(0x1F 0x8B) 字节流，内容为 UTF-8 文本。读取端自动识别明文/压缩，无需配套变更。

要点：
- 只改写仍是明文（typeof(content)='text'）且长度 ≥ 阈值的章节；
  已是 gzip blob 的行自动跳过 → **可断点续跑**，重复执行安全；
- 分批事务提交，实时进度与速率；
- 建议先自行备份库文件；收尾可用 --vacuum 回收空间、--check 做完整性校验。

用法：
    python3 tool/migrate_compress_content.py /path/to/novelmgt.db \
        [--threshold-chars 0] [--batch 500] [--vacuum] [--check] [--dry-run]

参数：
    --threshold-chars  只压缩字符数 ≥ 阈值的章节；0 = 全部压缩（默认 0，
                       与桌面端 ContentCodec 的 4096 不同：存量库一次性迁移，
                       全压缩收益最大，读取端无感知）
    --batch            每批提交的章节数（默认 500）
    --vacuum           迁移完成后 VACUUM 回收空间（需要约等于库大小的临时空间）
    --check            迁移后跑 PRAGMA quick_check 并抽样验证 gzip 可解压
    --dry-run          只统计将迁移的行数与字节数，不写入
"""

import argparse
import gzip
import sqlite3
import sys
import time

GZIP_MAGIC = b"\x1f\x8b"


def human(n):
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024 or u == "GB":
            return "%.2f%s" % (n / (1 << (10 * ["B", "KB", "MB", "GB"].index(u))), u)
    return "%dB" % n


def count_pending(con, threshold):
    row = con.execute(
        "SELECT COUNT(*), COALESCE(SUM(length(CAST(content AS BLOB))), 0) "
        "FROM chapters WHERE typeof(content)='text' AND length(content) >= ?",
        (threshold,),
    ).fetchone()
    return row[0], row[1]


def migrate(path, threshold, batch, vacuum, check, dry_run):
    con = sqlite3.connect(path, isolation_level=None, timeout=60)
    con.execute("PRAGMA busy_timeout=60000")

    page_count = con.execute("PRAGMA page_count").fetchone()[0]
    page_size = con.execute("PRAGMA page_size").fetchone()[0]
    print("库文件: %s" % path)
    print("当前大小: %s（%d 页 × %d B）" % (human(page_count * page_size), page_count, page_size))

    pending_n, pending_bytes = count_pending(con, threshold)
    print("待压缩章节（明文且 ≥ %d 字符）: %d 个 / 正文 %s" % (threshold, pending_n, human(pending_bytes)))
    if pending_n == 0:
        print("没有需要迁移的章节。")
    elif dry_run:
        print("（dry-run，不写入）")
        con.close()
        return

    t0 = time.time()
    done = raw_total = zip_total = 0
    last_id = 0
    while True:
        rows = con.execute(
            "SELECT id, content FROM chapters "
            "WHERE typeof(content)='text' AND length(content) >= ? AND id > ? "
            "ORDER BY id LIMIT ?",
            (threshold, last_id, batch),
        ).fetchall()
        if not rows:
            break
        con.execute("BEGIN")
        try:
            for cid, text in rows:
                blob = gzip.compress(text.encode("utf-8"), 6)
                con.execute("UPDATE chapters SET content=? WHERE id=?", (sqlite3.Binary(blob), cid))
                last_id = cid
                done += 1
                raw_total += len(text.encode("utf-8"))
                zip_total += len(blob)
            con.execute("COMMIT")
        except Exception:
            con.execute("ROLLBACK")
            raise
        elapsed = time.time() - t0
        rate = done / elapsed if elapsed else 0
        remain = (pending_n - done) / rate if rate else 0
        sys.stdout.write(
            "\r已压缩 %d/%d 章（id≤%d）| 原文 %s → %s | %.0f 章/秒 | 预计剩余 %d 分 %02d 秒   "
            % (done, pending_n, last_id, human(raw_total), human(zip_total),
               rate, int(remain // 60), int(remain % 60))
        )
        sys.stdout.flush()

    print()
    if done:
        after_n, _ = count_pending(con, threshold)
        page_count2 = con.execute("PRAGMA page_count").fetchone()[0]
        print("迁移完成: 压缩 %d 章，剩余明文待压 %d 个" % (done, after_n))
        print("迁移后库大小: %s" % human(page_count2 * page_size))

    if vacuum and not dry_run and done:
        print("VACUUM 中（重写整库，需要几分钟）…")
        t1 = time.time()
        con.execute("VACUUM")
        page_count3 = con.execute("PRAGMA page_count").fetchone()[0]
        print("VACUUM 完成，用时 %d 分 %02d 秒，最终大小: %s"
              % (int((time.time() - t1) // 60), int((time.time() - t1) % 60),
                 human(page_count3 * page_size)))

    if check and not dry_run:
        print("quick_check …")
        r = con.execute("PRAGMA quick_check").fetchone()[0]
        print("quick_check:", r)
        if r == "ok":
            bad = 0
            for cid, blob in con.execute(
                "SELECT id, content FROM chapters WHERE typeof(content)='blob' "
                "ORDER BY RANDOM() LIMIT 50"
            ):
                if bytes(blob)[:2] != GZIP_MAGIC:
                    bad += 1
                    continue
                gzip.decompress(bytes(blob)).decode("utf-8", "replace")
            print("抽样 50 个 blob 解压: %s" % ("全部通过" if bad == 0 else "%d 个异常" % bad))

    con.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("db", help="novelmgt.db 路径")
    ap.add_argument("--threshold-chars", type=int, default=0, help="只压缩字符数 ≥ 阈值的章节（0=全部）")
    ap.add_argument("--batch", type=int, default=500)
    ap.add_argument("--vacuum", action="store_true", help="完成后 VACUUM 回收空间")
    ap.add_argument("--check", action="store_true", help="完成后 quick_check + 抽样解压验证")
    ap.add_argument("--dry-run", action="store_true", help="只统计，不写入")
    args = ap.parse_args()
    migrate(args.db, args.threshold_chars, args.batch, args.vacuum, args.check, args.dry_run)


if __name__ == "__main__":
    main()
