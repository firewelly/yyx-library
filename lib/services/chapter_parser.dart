/// 章节解析器 - TXT 章节识别与中文数字转换
class ChapterParser {
  ChapterParser._();

  /// 章节标题正则列表（按优先级排列）
  static final List<RegExp> chapterPatterns = [
    // 第X章 格式 (如：第一章、第12章、第一百二十三章)
    RegExp(r'^第[一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+章\s*.+', caseSensitive: false),
    // 第X节 格式
    RegExp(r'^第[一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+节\s*.+', caseSensitive: false),
    // 第X回 格式 (如：第五回、第23回)
    RegExp(r'^第[一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+回\s*.+', caseSensitive: false),
    // 第X卷 格式
    RegExp(r'^第[一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+卷\s*.+', caseSensitive: false),
    // Chapter X 格式
    RegExp(r'^[Cc]hapter\s+\d+.*', caseSensitive: false),
    // 纯数字章节 (如：1. 标题 / 1、标题 / 第一章 标题)
    RegExp(r'^\d+[、.．]\s*\S+'),
    // 卷X 格式
    RegExp(r'^卷[一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+\s*.+', caseSensitive: false),
  ];

  /// 中文数字映射（扩展版，支持大写数字）
  static const Map<String, int> _chineseNumMap = {
    '零': 0, '〇': 0,
    '一': 1, '壹': 1,
    '二': 2, '贰': 2,
    '三': 3, '叁': 3,
    '四': 4, '肆': 4,
    '五': 5, '伍': 5,
    '六': 6, '陆': 6,
    '七': 7, '柒': 7,
    '八': 8, '捌': 8,
    '九': 9, '玖': 9,
    '十': 10, '拾': 10,
    '百': 100, '佰': 100,
    '千': 1000, '仟': 1000,
    '万': 10000, '萬': 10000,
    '亿': 100000000, '億': 100000000,
  };

  /// 中文数字转整数（完整版，参考 Python reorder_chapters_v3.py）
  static int chineseToInt(String chinese) {
    if (chinese.isEmpty) return 0;

    // 纯数字直接返回
    final numValue = int.tryParse(chinese);
    if (numValue != null) return numValue;

    // 处理特殊情况："十" = 10, "十一" = 11
    if (chinese == '十' || chinese == '拾') return 10;
    if ((chinese.startsWith('十') || chinese.startsWith('拾')) && chinese.length > 1) {
      final rest = chinese.substring(1);
      final restValue = _chineseNumMap[rest];
      if (restValue != null && restValue < 10) {
        return 10 + restValue;
      }
    }

    int result = 0;
    int unit = 1;
    int lastDigit = 0;
    bool hasUnit = false;

    // 从右向左解析（参考 Python 版本算法）
    for (int i = chinese.length - 1; i >= 0; i--) {
      final char = chinese[i];
      final value = _chineseNumMap[char];
      if (value == null) continue;

      if (value >= 10) {
        // 单位字符 (十, 百, 千, 万, 亿)
        hasUnit = true;
        if (value > unit) {
          unit = value;
          lastDigit = 0;
        } else {
          unit = value;
        }
      } else {
        // 数字字符
        if (lastDigit == 0) {
          result += value * unit;
        } else {
          // 处理连续数字
          result += value * (unit ~/ 10);
        }
        lastDigit = value;
      }
    }

    // 处理没有单位的情况 (如 "十一", "二十三")
    if (!hasUnit && chinese.length > 1) {
      final first = _chineseNumMap[chinese[0]];
      final second = _chineseNumMap[chinese[1]];
      if (first != null && second != null && first >= 10) {
        result = first + second;
      } else if (first != null && second != null) {
        result = first * 10 + second;
      }
    }

    return result;
  }

  /// 从章节标题中提取章节号
  static int? extractChapterNumber(String title) {
    // 先匹配 "第X章/节/回" 模式
    final patterns = [
      RegExp(r'第([一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+)章'),
      RegExp(r'第([一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+)节'),
      RegExp(r'第([一二三四五六七八九十百千万零〇壹贰叁肆伍陆柒捌玖拾佰仟萬億\d]+)回'),
      RegExp(r'[Cc]hapter\s+(\d+)'),
      RegExp(r'^(\d+)[、.．]'),
      // 纯数字章节标题
      RegExp(r'^(\d+)$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(title);
      if (match != null) {
        final numStr = match.group(1)!;
        final num = int.tryParse(numStr) ?? chineseToInt(numStr);
        if (num > 0) return num;
      }
    }
    return null;
  }

  /// 解析完整文本为章节列表
  /// [fullText] - 完整小说文本
  /// [bookTitle] - 书名（无章节时作为默认标题）
  /// 返回有序的章节列表（originalOrder 保存原始位置）
  static List<ParsedChapter> parseChapters(String fullText, {String bookTitle = ''}) {
    final lines = fullText.split(RegExp(r'\r?\n'));
    final List<ParsedChapter> chapters = [];
    final List<String> currentContent = [];
    String currentTitle = '';
    int currentNumber = 0;
    int originalOrder = 0;
    int startLine = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.isEmpty) {
        currentContent.add(lines[i]);
        continue;
      }

      // 检查是否匹配章节模式
      if (_isChapterTitle(line)) {
        // 保存前一章
        if (currentTitle.isNotEmpty || currentContent.isNotEmpty) {
          final content = _cleanContent(currentContent);
          if (content.isNotEmpty) {
            originalOrder++;
            chapters.add(ParsedChapter(
              title: currentTitle.isNotEmpty ? currentTitle : '第${chapters.length + 1}章',
              content: content,
              chapterNumber: currentNumber > 0 ? currentNumber : originalOrder,
              originalOrder: originalOrder,
              startLine: startLine,
            ));
          }
        }

        // 开始新章节
        currentTitle = line;
        currentNumber = extractChapterNumber(line) ?? 0; // 0 表示无法提取
        currentContent.clear();
        startLine = i;
      } else {
        currentContent.add(lines[i]);
      }
    }

    // 保存最后一章
    if (currentTitle.isNotEmpty || currentContent.isNotEmpty) {
      final content = _cleanContent(currentContent);
      if (content.isNotEmpty) {
        originalOrder++;
        chapters.add(ParsedChapter(
          title: currentTitle.isNotEmpty ? currentTitle : '第${chapters.length + 1}章',
          content: content,
          chapterNumber: currentNumber > 0 ? currentNumber : originalOrder,
          originalOrder: originalOrder,
          startLine: startLine,
        ));
      }
    }

    // 如果没有找到章节，整篇作为一个章节
    if (chapters.isEmpty) {
      chapters.add(ParsedChapter(
        title: bookTitle.isNotEmpty ? bookTitle : '全文',
        content: _cleanContent(fullText.split(RegExp(r'\r?\n'))),
        chapterNumber: 1,
        originalOrder: 1,
        startLine: 0,
      ));
    }

    // 按章节号排序（能提取编号的按编号，否则按原始顺序）
    _sortAndDeduplicate(chapters);

    return chapters;
  }

  /// 判断一行文本是否为章节标题
  static bool _isChapterTitle(String line) {
    for (final pattern in chapterPatterns) {
      if (pattern.hasMatch(line)) return true;
    }
    return false;
  }

  /// 清理章节内容
  static String _cleanContent(List<String> lines) {
    // 去除首尾空行
    int start = 0;
    int end = lines.length - 1;
    while (start < lines.length && lines[start].trim().isEmpty) { start++; }
    while (end > start && lines[end].trim().isEmpty) { end--; }

    if (start > end) return '';
    return lines.sublist(start, end + 1).join('\n');
  }

  /// 排序与去重（改进版）
  /// 策略：能提取编号的按编号排序，无法提取编号的按原始顺序排序
  /// 去重：先基于标题去重，再基于内容相似度去重
  static void _sortAndDeduplicate(List<ParsedChapter> chapters) {
    // 分离：有编号的 vs 无编号的
    final withNumber = <ParsedChapter>[];
    final withoutNumber = <ParsedChapter>[];

    for (final ch in chapters) {
      if (ch.extractedNumber != null && ch.extractedNumber! > 0) {
        withNumber.add(ch);
      } else {
        withoutNumber.add(ch);
      }
    }

    // 有编号的按编号排序
    withNumber.sort((a, b) {
      final numA = a.extractedNumber ?? a.chapterNumber;
      final numB = b.extractedNumber ?? b.chapterNumber;
      return numA.compareTo(numB);
    });

    // 无编号的按原始顺序排序
    withoutNumber.sort((a, b) => a.originalOrder.compareTo(b.originalOrder));

    // 合并：有编号的在前，无编号的在后
    chapters.clear();
    chapters.addAll(withNumber);
    chapters.addAll(withoutNumber);

    // 第一步：基于标题去重
    final seenTitles = <String>{};
    chapters.removeWhere((ch) {
      if (seenTitles.contains(ch.title)) return true;
      seenTitles.add(ch.title);
      return false;
    });

    // 第二步：基于内容相似度去重（内容完全相同视为重复）
    final seenContentHashes = <String>{};
    final uniqueChapters = <ParsedChapter>[];
    
    for (final ch in chapters) {
      // 使用内容的 hash 来判断是否相同（截取前1000字符计算hash以提高效率）
      final contentHash = _computeContentHash(ch.content);
      if (!seenContentHashes.contains(contentHash)) {
        seenContentHashes.add(contentHash);
        uniqueChapters.add(ch);
      } else {
        // 内容重复，跳过（诊断信息；service 层不依赖 flutter，故用 print）
        // ignore: avoid_print
        print('警告: 发现内容重复的章节 \'${ch.title}\'，已跳过');
      }
    }
    
    chapters.clear();
    chapters.addAll(uniqueChapters);

    // 重新编号（final chapterNumber = 1, 2, 3...）
    for (int i = 0; i < chapters.length; i++) {
      chapters[i] = chapters[i].copyWith(chapterNumber: i + 1);
    }
  }

  /// 计算内容的 hash（用于快速判断内容是否相同）
  static String _computeContentHash(String content) {
    // 取前1000字符计算简单hash，避免全文比较
    final sample = content.length > 1000 ? content.substring(0, 1000) : content;
    // 使用简单的字符累加hash
    int hash = 0;
    for (int i = 0; i < sample.length; i++) {
      hash = (hash * 31 + sample.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    // 同时考虑内容长度，防止短内容hash碰撞
    return '$hash-${content.length}';
  }
}

/// 解析后的章节数据
class ParsedChapter {
  final String title;
  final String content;
  final int chapterNumber;     // 最终排序后的编号 (1, 2, 3...)
  final int originalOrder;     // 文件中的原始位置顺序
  final int? extractedNumber;  // 从标题提取的原始编号（可能为null）
  final int startLine;

  const ParsedChapter({
    required this.title,
    required this.content,
    required this.chapterNumber,
    required this.originalOrder,
    this.extractedNumber,
    required this.startLine,
  });

  ParsedChapter copyWith({
    String? title,
    String? content,
    int? chapterNumber,
    int? originalOrder,
    int? extractedNumber,
    int? startLine,
  }) {
    return ParsedChapter(
      title: title ?? this.title,
      content: content ?? this.content,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      originalOrder: originalOrder ?? this.originalOrder,
      extractedNumber: extractedNumber ?? this.extractedNumber,
      startLine: startLine ?? this.startLine,
    );
  }
}