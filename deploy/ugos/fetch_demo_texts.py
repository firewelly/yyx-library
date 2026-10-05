#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取公版古籍原文（维基文库），生成示例书库文本缓存。

用于 `make_demo_db.py` 构建随包分发的示例书库（首次安装尚无自有书库时的
默认书库）。全部为公有领域古籍原文（明清白话小说），不含现代版权内容。

用法：
    python3 fetch_demo_texts.py [--only 西游记] [--out demo_texts]

输出：demo_texts/<slug>.json
    {"work": ..., "author": ..., "chapters": [{"title": ..., "text": ...}, ...]}

- 逐章写入缓存并支持断点续传（重新运行会跳过已抓取章节）；
- 繁体转简体使用 zhconv（pip install zhconv）；
- 文本来源：维基文库 https://zh.wikisource.org （CC BY-SA 4.0 / 公有领域原文）。
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from html import unescape

API = "https://zh.wikisource.org/w/api.php"
UA = ("novelmgt-demo-fetch/1.0 (personal library manager demo; "
      "https://github.com/firewelly/yyx-library)")

WORKS = [
    {
        "slug": "xiyouji",
        "page": "西遊記",
        "title": "西游记",
        "author": "吴承恩",
        "chapters": 100,
        "summary": "明代长篇小说，四大名著之一。全书一百回，"
                   "写孙悟空、猪八戒、沙僧护送唐僧西行取经，历九九八十一难。"
                   "（公版古籍，原文取自维基文库。）",
        "tags": ["古典名著", "神魔"],
    },
    {
        "slug": "sanguoyanyi",
        "page": "三國演義",
        "title": "三国演义",
        "author": "罗贯中",
        "chapters": 120,
        "summary": "元末明初长篇小说，四大名著之一。全书一百二十回，"
                   "叙东汉末年群雄割据至三国鼎立、西晋统一的历史。"
                   "（公版古籍，原文取自维基文库。）",
        "tags": ["古典名著", "历史"],
    },
    {
        "slug": "hongloumeng",
        "page": "紅樓夢",
        "title": "红楼梦",
        "author": "曹雪芹",
        "chapters": 120,
        "summary": "清代长篇小说，四大名著之一。全书一百二十回，"
                   "以贾府由盛而衰为背景，写宝玉、黛玉、宝钗等人的命运。"
                   "（公版古籍，原文取自维基文库。）",
        "tags": ["古典名著", "世情"],
    },
]


def api(retries=5, **params):
    params = dict(params, format="json", formatversion="2")
    url = API + "?" + urllib.parse.urlencode(params)
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2.0 * (i + 1))
    raise RuntimeError("接口请求失败: %s (%s)" % (url, last))


def strip_tags(html):
    return unescape(re.sub(r"(?is)<[^>]+>", "", html)).strip()


def find_chapter_pages(work_page, expect):
    """列出作品子页面，按回序排序（兼容 第001回 / 第一回 命名）"""
    d = api(action="query", list="allpages",
            apprefix=work_page + "/", aplimit="500")
    titles = [p["title"] for p in d.get("query", {}).get("allpages", [])]
    numbered = []
    for t in titles:
        m = re.search(r"第(\d{1,4})回$", t)
        if m:
            numbered.append((t, int(m.group(1))))
        else:
            m = re.search(r"/([一二三四五六七八九十百零〇]{1,6})$", t)
            if m:
                numbered.append((t, None))
    if len(numbered) < expect:
        raise RuntimeError("子页面数量不足: %s -> %d (<%d)"
                           % (work_page, len(numbered), expect))
    numbered.sort(key=lambda x: (x[1] is None, x[1] if x[1] is not None else 0))
    return [t for t, _ in numbered[:expect]]


NAV_PATTERNS = [
    re.compile(r"^\s*[←→]\s*$"),
    re.compile(r"^\s*姊妹计划"),
    re.compile(r"^\s*数据项\s*$"),
    re.compile(r"^\s*更多资料"),
    re.compile(r"^\s*版本信息\s*$"),
    re.compile(r"^\s*(上|下)一回[:：]?\s*$"),
    re.compile(r"^\s*目[　 ]?錄\s*$"),
    re.compile(r"^注意：本页面含有Unihan"),      # 页面编辑提示，非正文
    re.compile(r"^有关字符可能会错误显示"),
]


FOOTER_PATTERNS = [
    re.compile(r"^此作品在全世界都属于"),
    re.compile(r"^Public domain"),
    re.compile(r"^本作品"),
    re.compile(r"^公有领域"),
]


def clean_chapter(html):
    """从章节页 HTML 提取正文段落。

    章节页结构：导航表头（序号/回目/上下回链接） + 正文段落 + 版权模板。
    导航在 <table> 内，正文在 <p> 里，页尾还有 HTML 注释形式的解析报告。
    """
    html = re.sub(r"(?s)<!--.*?-->", "", html)
    html = re.sub(r"(?is)<table.*?</table>", "", html)          # 表头/上下回导航
    html = re.sub(r"(?is)<style.*?</style>", "", html)
    html = re.sub(r"(?is)<script.*?</script>", "", html)
    html = re.sub(r"(?is)<sup[^>]*reference[^>]*>.*?</sup>", "", html)
    html = re.sub(r'(?is)<div[^>]*class="[^"]*licensetpl[^"]*"[^>]*>.*?</div>', "", html)
    html = re.sub(r"(?is)<br\s*/?>", "\n", html)
    html = re.sub(r"(?is)</(p|div|li|dd|dt|h[1-6])>", "\n\n", html)
    text = unescape(re.sub(r"(?is)<[^>]+>", "", html))

    lines, out = text.split("\n"), []
    for line in lines:
        line = re.sub(r"[ \t\u00a0]+", " ", line).strip()
        if not line:
            if out and out[-1] != "":
                out.append("")
            continue
        if any(p.search(line) for p in NAV_PATTERNS):
            continue
        if any(p.search(line) for p in FOOTER_PATTERNS):
            break                                    # 版权声明及其后内容不属于正文
        out.append(line)
    body = "\n".join(out).strip()
    body = re.sub(r"\n{3,}", "\n\n", body)
    return body


CHAPTER_NO = r"第[0-9一二三四五六七八九十百零〇]+回"


def title_ok(title):
    """标题是否已含回次与回目（缺回目的需要重抓）"""
    return bool(re.match(r"^%s\s*\S" % CHAPTER_NO, title or ""))


def chapter_title(html, fallback):
    """章节标题（回次 + 回目）。

    各作品表头模板不同，逐个兼容：
      西游记   <td style="width:50%">作品<br/>第一回<br/>回目</td>
      三国演义 <td style="width:70%">第一回　<b>回目</b></td>
      红楼梦   <div class="center"><b>第一回 回目</b></div>
    """
    # 1) 三段式表头：作品 / 回次 / 回目
    m = re.search(r'<td style="width:50%;">(.*?)</td>', html, re.S)
    if m:
        parts = [strip_tags(x) for x in re.split(r"(?is)<br\s*/?>", m.group(1))]
        parts = [p for p in parts if p and not p.startswith("作者")]
        if len(parts) >= 3:
            return ("%s %s" % (parts[1], parts[2])).strip()
        if len(parts) == 2:
            return parts[1]

    # 2) 回次后紧跟加粗回目
    m = re.search(r"(?s)(%s)[\s\u3000]*<b>(.+?)</b>" % CHAPTER_NO, html)
    if m:
        return "%s %s" % (strip_tags(m.group(1)), strip_tags(m.group(2)))

    # 3) 整行加粗的回目（回次与回目同在一行）
    m = re.search(r'(?is)<div class="center">\s*<b>(.*?)</b>', html)
    if m:
        title = strip_tags(m.group(1)).strip()
        if title:
            return title

    return fallback


def _page_num(page):
    m = re.search(r"第(\d{1,4})回$", page)
    return int(m.group(1)) if m else 0


def save_cache(path, cache):
    cache["chapters"].sort(key=lambda c: _page_num(c["page"]))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False, separators=(",", ":"))


def fetch_work(work, out_dir):
    path = os.path.join(out_dir, "%s.json" % work["slug"])
    cache = {"work": work["title"], "author": work["author"],
             "page": work["page"], "chapters": []}
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            cache = json.load(f)

    # 标题缺回目的章节丢弃重抓（早期模板解析不全）
    retry = [c for c in cache["chapters"] if not title_ok(c.get("title"))]
    if retry:
        sys.stdout.write("[%s] %d 章标题缺回目，重新抓取\n"
                         % (work["title"], len(retry)))
        cache["chapters"] = [c for c in cache["chapters"] if title_ok(c.get("title"))]

    done = {c["page"] for c in cache["chapters"]}
    pages = find_chapter_pages(work["page"], work["chapters"])
    sys.stdout.write("[%s] 待抓取 %d 章（已有 %d）\n"
                     % (work["title"], len(pages), len(done)))
    sys.stdout.flush()

    for idx, page in enumerate(pages, start=1):
        if page in done:
            continue
        try:
            d = api(action="parse", page=page, prop="text")
            if "error" in d:
                raise RuntimeError(d["error"].get("info", "parse error"))
            html = d["parse"]["text"]
            text = clean_chapter(html)
            if len(text) < 200:
                raise RuntimeError("正文过短(%d 字)，疑似页面结构变化" % len(text))
            cache["chapters"].append({
                "page": page,
                "title": chapter_title(html, "第%d回" % idx),
                "text": text,
            })
        except Exception as e:  # noqa: BLE001
            sys.stdout.write("\n[%s] 第 %d 章失败: %s\n" % (work["title"], idx, e))
            sys.stdout.flush()
            time.sleep(3)
            continue
        if idx % 10 == 0 or idx == len(pages):
            save_cache(path, cache)
            sys.stdout.write("\r[%s] %d/%d 已抓取"
                             % (work["title"], len(cache["chapters"]), len(pages)))
            sys.stdout.flush()
        time.sleep(0.6)

    save_cache(path, cache)
    sizes = sum(len(c["text"]) for c in cache["chapters"])
    sys.stdout.write("\n[%s] 完成: %d 章 / %d 字 -> %s\n"
                     % (work["title"], len(cache["chapters"]), sizes, path))
    sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "demo_texts"))
    ap.add_argument("--only", default="", help="只抓取指定 slug")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for work in WORKS:
        if args.only and work["slug"] != args.only:
            continue
        try:
            fetch_work(work, args.out)
        except Exception as e:  # noqa: BLE001
            sys.stdout.write("[%s] 跳过: %s\n" % (work["title"], e))
            sys.stdout.flush()


if __name__ == "__main__":
    main()
