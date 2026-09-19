import 'dart:convert';
import 'dart:typed_data';
import 'package:kindle_unpack/kindle_unpack.dart';
import '../utils/html_text.dart';
import 'chapter_parser.dart';
import 'platform_fs.dart';

/// MOBI / AZW / AZW3 / KF8 导入器
///
/// 使用 [kindle_unpack](https://pub.dev/packages/kindle_unpack) 纯 Dart 解析。
/// 该库不做 DRM 移除 —— 仅解析无 DRM 保护的文件。
/// 若文件受 DRM 保护,解析会失败并抛出 [MobiImportException]。
class MobiImporter {
  MobiImporter._();

  /// 解析 Kindle 文件,返回书名、作者与切分后的章节列表
  ///
  /// [filePath] MOBI/AZW/AZW3 文件路径
  /// [bookTitle] 可选书名,默认从元数据或文件名推导
  static Future<({String title, String? author, List<ParsedChapter> chapters})>
      parse(String filePath, {String? bookTitle}) async {
    final bytes = await PlatformFs.readBytes(filePath);
    if (bytes == null) {
      throw MobiImportException('文件不存在: $filePath');
    }
    return parseBytes(
      bytes,
      bookTitle: bookTitle,
      fileName: _fileNameFromPath(filePath),
    );
  }

  /// 解析内存中的 Kindle 文件字节（桌面与 Web 通用）
  ///
  /// [fileName] 仅用于书名兜底推导（元数据缺失时）
  static Future<({String title, String? author, List<ParsedChapter> chapters})>
      parseBytes(Uint8List bytes, {String? bookTitle, String? fileName}) async {

    KindleBook book;
    try {
      book = KindleBook.fromBytes(bytes);
    } on FormatException catch (e) {
      // DRM 或格式损坏都会在此抛出
      final msg = e.message.toLowerCase();
      if (msg.contains('drm') || msg.contains('decrypt') || msg.contains('protect')) {
        throw MobiImportException('该 Kindle 文件受 DRM 保护,无法解析。\nDRM 受保护文件不支持导入。');
      }
      throw MobiImportException('Kindle 文件解析失败:${e.message}\n文件可能已损坏或格式不受支持。');
    } catch (e) {
      throw MobiImportException('Kindle 文件解析失败:$e');
    }

    // 元数据
    final title = bookTitle ??
        (book.title.isNotEmpty ? book.title : _titleFromName(fileName ?? ''));
    final authors = book.exth?.authors ?? const <String>[];
    final author = authors.isNotEmpty ? authors.join(', ') : null;

    // rawML 是完整 HTML 文本(KF8)或单个 HTML blob(MOBI-7)
    final rawHtml = utf8.decode(book.rawML, allowMalformed: true);
    final plainText = HtmlText.stripHtml(rawHtml, preserveParagraphs: true);

    if (plainText.trim().isEmpty) {
      throw MobiImportException('Kindle 文件内容为空,无法提取文字。');
    }

    // 复用章节解析器切分章节
    final chapters = ChapterParser.parseChapters(plainText, bookTitle: title);

    return (title: title, author: author, chapters: chapters);
  }

  /// 从文件名推导书名
  static String _titleFromName(String name) {
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    return nameWithoutExt.replaceAll(RegExp(r'[_\-]'), ' ').trim();
  }

  /// 从文件路径提取文件名（兼容 / 与 \ 分隔符）
  static String _fileNameFromPath(String filePath) =>
      filePath.split(RegExp(r'[/\\]')).last;
}

/// MOBI/Kindle 导入异常
class MobiImportException implements Exception {
  final String message;
  MobiImportException(this.message);

  @override
  String toString() => message;
}
