#!/usr/bin/env python3
"""提取 lib/ 下所有 t('...') 的 key（含相邻字符串合并），输出 /tmp/runtime_keys.json。

用法：python3 scripts/extract_l10n_keys.py && python3 scripts/gen_translations.py

说明：
- 只认 t(...) 调用里的字符串字面量；注释、raw 字符串、三引号跳过；
- 相邻字符串字面量按 Dart 隐式拼接合并（如 'A'\n'B' → 'AB'）；
- 运行时传入的 key（t(palette.name)、t(rt.name)、t(label)、t(book.status) 等）无法静态提取，
  统一维护在 KNOWN_VALUE_KEYS。
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, 'lib')
CJK = re.compile(r'[\u4e00-\u9fff]')
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
T_OPEN = re.compile(r"\bt\(\s*")

# 运行时传入的 key（数据值/常量），必须与显示层 t(x) 的取值一致
KNOWN_VALUE_KEYS = [
    # 书籍状态（AppConstants.bookStatuses，DB 存中文）
    '连载中', '已完结',
    # 配色方案名（AppPalette.name）
    '墨韵书阁', '靛蓝墨海', '暮色书房', '墨夜星河',
    # 阅读主题名（kReaderThemes.name）
    '纯白', '米黄', '深黑', '浅绿',
    # 编码选项（TextDecode.encodingOptions 的 label）
    '自动检测', 'Big5（繁体）',
    # 设置页语言分段
    '简体中文',
]


def find_triple(text, i, q):
    pat = q * 3
    j, n = i, len(text)
    while j < n:
        if text[j] == '\\':
            j += 2
            continue
        if text.startswith(pat, j):
            return j + 3
        j += 1
    return n


def scan_simple_string(text, i, c, raw=False):
    n = len(text)
    j = i + 1
    stack = []
    while j < n:
        ch = text[j]
        if raw:
            if ch == c:
                return j + 1
            j += 1
            continue
        if ch == '\\':
            j += 2
            continue
        if not stack:
            if ch == c:
                return j + 1
            if ch == '$' and j + 1 < n and text[j + 1] == '{':
                stack.append(1)
                j += 2
                continue
        else:
            if ch == '{':
                stack[-1] += 1
            elif ch == '}':
                stack[-1] -= 1
                if stack[-1] == 0:
                    stack.pop()
                    j += 1
                    continue
            elif ch in '\'"':
                j = scan_simple_string(text, j, ch)
                continue
        j += 1
    return n


def scan_tokens(text):
    toks = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and text[i:i + 2] == '//':
            j = text.find('\n', i)
            j = n if j < 0 else j
            toks.append(('comment', i, j)); i = j
        elif c == '/' and text[i:i + 2] == '/*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            toks.append(('comment', i, j)); i = j
        elif c in '\'"':
            if text[i:i + 3] == c * 3:
                j = find_triple(text, i + 3, c)
                toks.append(('str3', i, j)); i = j
            else:
                raw = i > 0 and text[i - 1] in 'rR' and (
                    i < 2 or not (text[i - 2].isalnum() or text[i - 2] == '_'))
                j = scan_simple_string(text, i, c, raw)
                toks.append(('rawstr' if raw else 'str', i, j)); i = j
        else:
            i += 1
    return toks


def unescape(s):
    return (s.replace('\\\\', '\x00')
             .replace('\\n', '\n').replace('\\t', '\t').replace("\\'", "'")
             .replace('\x00', '\\'))


def main():
    keys = set(KNOWN_VALUE_KEYS)
    for dp, _, fns in os.walk(LIB):
        for fn in sorted(fns):
            if not fn.endswith('.dart') or fn.endswith('.g.dart'):
                continue
            src = open(os.path.join(dp, fn), encoding='utf-8').read()
            toks = scan_tokens(src)
            strpos = [(a, b) for k, a, b in toks if k == 'str']
            for m in T_OPEN.finditer(src):
                cur = m.end()
                parts = []
                while True:
                    nxt = None
                    for (a, b) in strpos:
                        if a >= cur and src[cur:a].strip() == '':
                            nxt = (a, b)
                            break
                    if not nxt:
                        break
                    parts.append(src[nxt[0]:nxt[1]])
                    cur = nxt[1]
                if parts:
                    body = unescape(''.join(x[1:-1] for x in parts))
                    if CJK.search(body):
                        keys.add(body)
    out = sorted(keys)
    json.dump(out, open('/tmp/runtime_keys.json', 'w'), ensure_ascii=False, indent=0)
    print(f'extracted {len(out)} keys -> /tmp/runtime_keys.json')


if __name__ == '__main__':
    main()
