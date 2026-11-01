#!/usr/bin/env python3
"""OneDrive 小说批量导入 YYX书库（经服务端 API，忠实移植 Dart ChapterParser）。

用法：
  python3 bulk_import_onedrive.py --base http://192.168.3.146:12702 \
      --dir "/path/to/H" [--dir "/path/to/novels"] [--limit N] [--validate-only]

设计：
- 编码探测与宽容解码、章节切分、去重排序：逐行对照 lib/services/chapter_parser.dart
  与 lib/utils/text_decode.dart 移植（Python gb18030 为 gbk 超集，四字节序列直接
  解出真字，保真度优于 Dart 端的 U+FFFD 替换；切章行为一致）。
- 书名派生与客户端一致：去 .txt → -/_ 替换为空格 → trim。
- 去重：与客户端 findBookByTitleAndAuthor 同语义（书名精确匹配；另做同名任意作者
  预过滤，保守跳过避免重复建书）。
- 断点续跑：state.json 记录 done/skip/failed（按文件路径+mtime），重跑自动跳过。
- 章节正文 >4096 字由服务端 gzip 压缩（与 ContentCodec 对齐）。
"""
import argparse
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

# ============ Dart ChapterParser 移植 ============

NUM_CHARS = "一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\\d"
PUNCT = "。，！？；、“”‘’「」《》"

CHAPTER_PATTERNS = [
    re.compile(rf"^第[{NUM_CHARS}]+章\s*.+"),
    re.compile(rf"^第[{NUM_CHARS}]+节\s*.+"),
    re.compile(rf"^第[{NUM_CHARS}]+回\s*.+"),
    re.compile(rf"^第[{NUM_CHARS}]+卷\s*.+"),
    re.compile(r"^[Cc]hapter\s+\d+.*"),
    re.compile(r"^\d+[、.．]\s*\S+"),
    re.compile(r"^卷[一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+\s*.+"),
]

EXTRACT_PATTERNS = [
    re.compile(rf"第([{NUM_CHARS}]+)章"),
    re.compile(rf"第([{NUM_CHARS}]+)节"),
    re.compile(rf"第([{NUM_CHARS}]+)回"),
    re.compile(r"[Cc]hapter\s+(\d+)"),
    re.compile(r"^(\d+)[、.．]"),
    re.compile(r"^(\d+)$"),
]

CHINESE_NUM_MAP = {
    "零": 0, "〇": 0, "一": 1, "壹": 1, "二": 2, "贰": 2, "三": 3, "叁": 3,
    "四": 4, "肆": 4, "五": 5, "伍": 5, "六": 6, "陆": 6, "七": 7, "柒": 7,
    "八": 8, "捌": 8, "九": 9, "玖": 9, "十": 10, "拾": 10, "百": 100, "佰": 100,
    "千": 1000, "仟": 1000, "万": 10000, "萬": 10000, "亿": 100000000, "億": 100000000,
}


def chineseToInt(chinese: str) -> int:
    if not chinese:
        return 0
    try:
        return int(chinese)
    except ValueError:
        pass
    if chinese in ("十", "拾"):
        return 10
    if chinese[0] in ("十", "拾") and len(chinese) > 1:
        rest = CHINESE_NUM_MAP.get(chinese[1:])
        if rest is not None and rest < 10:
            return 10 + rest
    result, unit, last_digit, has_unit = 0, 1, 0, False
    for ch in reversed(chinese):
        value = CHINESE_NUM_MAP.get(ch)
        if value is None:
            continue
        if value >= 10:
            has_unit = True
            unit = value
        else:
            if last_digit == 0:
                result += value * unit
            else:
                result += value * (unit // 10)
            last_digit = value
    if not has_unit and len(chinese) > 1:
        first = CHINESE_NUM_MAP.get(chinese[0])
        second = CHINESE_NUM_MAP.get(chinese[1])
        if first is not None and second is not None:
            if first >= 10:
                result = first + second
            else:
                result = first * 10 + second
    return result


def extract_chapter_number(title: str):
    for pat in EXTRACT_PATTERNS:
        m = pat.search(title)
        if m:
            num = chineseToInt(m.group(1))
            if num > 0:
                return num
    return None


def is_chapter_title(line: str) -> bool:
    if len(line) > 50:
        return False
    if re.search(r"[。，！？；、“”‘’「」《》]", line):
        return False
    return any(p.match(line) for p in CHAPTER_PATTERNS)


def compute_content_hash(content: str) -> str:
    sample = content[:1000]
    h = 0
    for ch in sample:
        h = (h * 31 + ord(ch)) & 0xFFFFFFFF
    return f"{h}-{len(content)}"


def sort_and_deduplicate(chapters: list) -> list:
    with_number = [c for c in chapters if c["extractedNumber"] and c["extractedNumber"] > 0]
    without_number = [c for c in chapters if not (c["extractedNumber"] and c["extractedNumber"] > 0)]
    with_number.sort(key=lambda c: c["extractedNumber"] or c["chapterNumber"])
    without_number.sort(key=lambda c: c["originalOrder"])
    merged = with_number + without_number
    seen_titles, deduped = set(), []
    for c in merged:
        if c["title"] in seen_titles:
            continue
        seen_titles.add(c["title"])
        deduped.append(c)
    seen_hash, unique = set(), []
    for c in deduped:
        h = compute_content_hash(c["content"])
        if h not in seen_hash:
            seen_hash.add(h)
            unique.append(c)
    for i, c in enumerate(unique):
        c["chapterNumber"] = i + 1
    return unique


def parse_chapters(full_text: str, book_title: str = "") -> list:
    lines = re.split(r"\r?\n", full_text)
    chapters, current_content = [], []
    current_title, current_number, original_order, start_line = "", 0, 0, 0

    def save():
        nonlocal original_order
        # 对照 Dart _cleanContent：剥离首尾空行
        start, end = 0, len(current_content) - 1
        while start < len(current_content) and not current_content[start].strip():
            start += 1
        while end > start and not current_content[end].strip():
            end -= 1
        content = "\n".join(current_content[start:end + 1]) if start <= end else ""
        if not content.strip():
            return
        original_order += 1
        chapters.append({
            "title": current_title or f"第{len(chapters) + 1}章",
            "content": content,
            "chapterNumber": current_number if current_number > 0 else original_order,
            "originalOrder": original_order,
            "extractedNumber": current_number if current_number > 0 else None,
            "startLine": start_line,
        })

    for i, raw_line in enumerate(lines):
        line = raw_line.strip()
        if not line:
            current_content.append(raw_line)
            continue
        if is_chapter_title(line):
            save()
            current_title, current_number = line, extract_chapter_number(line) or 0
            current_content, start_line = [], i
        else:
            current_content.append(raw_line)
    save()
    if not chapters:
        chapters.append({
            "title": book_title or "全文",
            "content": "\n".join(lines).strip(),
            "chapterNumber": 1, "originalOrder": 1,
            "extractedNumber": None, "startLine": 0,
        })
    return sort_and_deduplicate(chapters)


# ============ 编码探测（对照 TextDecode） ============

def looks_valid_chinese(text: str) -> bool:
    suspicious = kana_pua = han = 0
    for ch in text[:2000]:
        cp = ord(ch)
        if cp == 0xFFFD or (cp < 0x20 and cp not in (10, 13, 9)):
            suspicious += 1
        elif (0x3040 <= cp <= 0x30FF) or (0xE000 <= cp <= 0xF8FF):
            kana_pua += 1
        elif 0x4E00 <= cp <= 0x9FFF:
            han += 1
    if suspicious > 10:
        return False
    if han > 0 and kana_pua / han > 0.005:
        return False
    if han == 0 and kana_pua > 0:
        return False
    return True


def decode_text(raw: bytes) -> str:
    try:
        t = raw.decode("utf-8")
        if looks_valid_chinese(t):
            return t
    except UnicodeDecodeError:
        pass
    t = raw.decode("gb18030", errors="replace")
    if looks_valid_chinese(t):
        return t
    try:
        t = raw.decode("big5", errors="replace")
        if looks_valid_chinese(t):
            return t
    except Exception:
        pass
    return raw.decode("utf-8", errors="replace")


def derive_title(filename: str) -> str:
    stem = filename[:-4] if filename.lower().endswith(".txt") else filename
    return re.sub(r"[-_]", " ", stem).strip()


# ============ 导入器 ============

class Importer:
    def __init__(self, base: str, state_path: Path):
        self.base = base.rstrip("/")
        self.state_path = state_path
        self.state = {"done": {}, "skip": {}, "failed": {}}
        if state_path.exists():
            self.state = json.loads(state_path.read_text())
        self.existing_titles = set()
        self.existing_any = set()

    def api(self, method, path, body=None, timeout=180):
        data = json.dumps(body).encode() if body is not None else (b"{}" if method in ("POST", "PUT", "DELETE") else None)
        req = urllib.request.Request(self.base + "/api" + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"} if data else {})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            text = r.read().decode()
            return json.loads(text) if text.strip() else None

    def preload_existing(self):
        page, total = 1, None
        while True:
            d = self.api("GET", f"/books?page={page}&perPage=200")
            total = d["total"]
            for b in d["books"]:
                self.existing_titles.add(b["title"])
                self.existing_any.add(b["title"])
            if page * 200 >= total:
                break
            page += 1
        print(f"[preload] 现有书籍 {total} 本（标题集合 {len(self.existing_titles)}）")

    def import_file(self, path: Path, source_label: str) -> str:
        title = derive_title(path.name)
        if title in self.existing_titles or title in self.existing_any:
            return "skip-existing"
        raw = path.read_bytes()
        text = decode_text(raw)
        chapters = parse_chapters(text, book_title=title)
        if not chapters:
            return "no-chapters"
        now = time.strftime("%Y-%m-%dT%H:%M:%S")
        word_count = sum(len(c["content"]) for c in chapters)
        book = self.api("POST", "/books", {
            "title": title, "status": "连载中", "sourceFormat": "txt",
            "filePath": f"{source_label}/{path.name}", "wordCount": word_count,
            "createdAt": now, "updatedAt": now,
        })
        bid = book["id"]
        for i in range(0, len(chapters), 300):
            batch = [{"chapterNumber": c["chapterNumber"], "originalOrder": c["originalOrder"],
                      "title": c["title"], "content": c["content"], "sourceFormat": "txt",
                      "createdAt": now, "updatedAt": now}
                     for c in chapters[i:i + 300]]
            self.api("POST", f"/books/{bid}/chapters", {"chapters": batch})
        return f"ok:{len(chapters)}"

    def run(self, dirs, limit=None, cached_only=False):
        files = []
        for d, label in dirs:
            p = Path(d)
            if not p.exists():
                print(f"[warn] 目录不存在: {p}")
                continue
            for f in sorted(p.rglob("*.txt")):
                if f.is_file() and not f.name.endswith(".crdownload") and "_trash" not in str(f):
                    files.append((f, label))
        if limit:
            files = files[:limit]
        print(f"[files] 待处理 {len(files)} 个文件")
        done_before = len(self.state["done"])
        t0 = time.time()
        processed = 0
        for idx, (f, label) in enumerate(files):
            key = f"{f}|{int(f.stat().st_mtime)}"
            if key in self.state["done"] or key in self.state["skip"] or key in self.state["failed"]:
                continue
            if cached_only:
                st = f.stat()
                if st.st_blocks * 512 < st.st_size * 0.9:
                    self.state["skip"][key] = {"title": title, "reason": "未缓存(云端，未导入)"}
                    continue
            title = derive_title(f.name)
            if title in self.existing_titles or title in self.existing_any:
                self.state["skip"][key] = {"title": title, "reason": "已存在"}
                self.existing_any.add(title)
            else:
                try:
                    r = self.import_file(f, label)
                    if r.startswith("ok:"):
                        self.state["done"][key] = {"title": title, "chapters": r[3:]}
                        self.existing_any.add(title)
                    elif r == "skip-existing":
                        self.state["skip"][key] = {"title": title, "reason": "导入时发现已存在"}
                    else:
                        self.state["failed"][key] = {"title": title, "reason": r}
                except Exception as e:
                    self.state["failed"][key] = {"title": title, "reason": repr(e)[:160]}
            processed += 1
            if processed % 25 == 0:
                self.state_path.write_text(json.dumps(self.state, ensure_ascii=False, indent=0))
                rate = processed / max(1e-9, time.time() - t0)
                remain = (len(files) - processed) / max(1e-9, rate)
                print(f"[{idx + 1}/{len(files)}] 完成 {processed} | "
                      f"导入 {len(self.state['done']) - done_before} | "
                      f"跳过 {len(self.state['skip'])} | 失败 {len(self.state['failed'])} | "
                      f"{rate:.1f} 文件/秒，预计剩余 {remain / 3600:.1f} 小时", flush=True)
        self.state_path.write_text(json.dumps(self.state, ensure_ascii=False, indent=0))
        print(f"[done] 导入 {len(self.state['done'])} | 跳过 {len(self.state['skip'])} | "
              f"失败 {len(self.state['failed'])} | 总耗时 {(time.time() - t0) / 3600:.2f} 小时")
        if self.state["failed"]:
            print("失败清单（前 20）:")
            for k, v in list(self.state["failed"].items())[:20]:
                print("  ", v["title"], "→", v["reason"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://192.168.3.146:12702")
    ap.add_argument("--dir", action="append", required=True, help="小说目录（可重复，格式: 路径 或 路径::标签）")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--cached-only", action="store_true", help="仅导入本地已缓存（已水合）的文件，云端文件跳过")
    ap.add_argument("--validate", action="store_true", help="仅对每目录前 3 个文件试解析，不写库")
    ap.add_argument("--state", default=str(Path(__file__).parent / "bulk_import_state.json"))
    args = ap.parse_args()

    dirs = []
    for d in args.dir:
        if "::" in d:
            path, label = d.split("::", 1)
        else:
            path, label = d, Path(d).name
        dirs.append((path, label))

    imp = Importer(args.base, Path(args.state))
    if args.validate:
        for path, label in dirs:
            for f in sorted(Path(path).glob("*.txt"))[:3]:
                raw = f.read_bytes()
                text = decode_text(raw)
                chs = parse_chapters(text, derive_title(f.name))
                print(f"[{label}] {f.name[:40]} → {len(chs)} 章 | "
                      f"首章: {chs[0]['title'][:30] if chs else '-'}")
        return

    imp.preload_existing()
    imp.run(dirs, args.limit, cached_only=args.cached_only)


if __name__ == "__main__":
    main()
