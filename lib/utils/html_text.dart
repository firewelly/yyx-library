/// HTML 文本处理工具 —— 供 EPUB/PDF/MOBI 导入器共用,
/// 保证各格式的 HTML → 纯文本转换行为一致。
class HtmlText {
  HtmlText._();

  /// 常见 HTML 命名实体 → 字符映射
  static const Map<String, String> _namedEntities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&lsquo;': '‘',
    '&rsquo;': '’',
    '&hellip;': '…',
    '&mdash;': '—',
    '&ndash;': '–',
    '&emsp;': '\u3000',
    '&ensp;': ' ',
    '&times;': '×',
    '&divide;': '÷',
    '&copy;': '©',
    '&reg;': '®',
  };

  /// 去除 HTML 标签并解码实体(保留段落结构)
  ///
  /// [preserveParagraphs] 为 true 时,块级标签(p/div/br/h1-6 等)转换为换行,
  /// 利于后续章节切分;否则直接删除标签。
  static String stripHtml(
    String html, {
    bool preserveParagraphs = false,
  }) {
    var text = html;

    if (preserveParagraphs) {
      // 块级标签转换为换行,保留段落结构
      text = text.replaceAll(
        RegExp(r'</?(p|div|br|h[1-6]|li|tr|blockquote)[^>]*>', caseSensitive: false),
        '\n',
      );
    }

    // 移除 script/style 内容
    text = text.replaceAll(
      RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true),
      '',
    );

    // 移除其余所有 HTML 标签
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // 解码命名实体
    _namedEntities.forEach((k, v) => text = text.replaceAll(k, v));

    // 解码数字实体 &#NNN; / &#xHH;
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.tryParse(m.group(1) ?? '0') ?? 0),
    );
    text = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.tryParse(m.group(1) ?? '0', radix: 16) ?? 0),
    );

    // 折叠多余空白与空行
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }
}
