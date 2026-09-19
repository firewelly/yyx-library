import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'chapter_parser.dart';
import 'platform_fs.dart';

/// PDF 导入器 —— 从文字版 PDF 抽取文本并切分章节
///
/// 注意:仅支持「文字版」PDF(内含可提取文本)。
/// 扫描版 PDF(纯图片)无法提取文字,会抛出 [PdfImportException]。
class PdfImporter {
  PdfImporter._();

  /// 解析 PDF 文件,返回书名与切分后的章节列表
  ///
  /// [filePath] PDF 文件路径
  /// [bookTitle] 可选书名,默认从文件名推导
  static Future<({String title, String? author, List<ParsedChapter> chapters})>
      parse(String filePath, {String? bookTitle}) async {
    final bytes = await PlatformFs.readBytes(filePath);
    if (bytes == null) {
      throw PdfImportException('文件不存在: $filePath');
    }
    return parseBytes(
      bytes,
      bookTitle: bookTitle,
      fileName: filePath.split(RegExp(r'[/\\]')).last,
    );
  }

  /// 解析内存中的 PDF 字节（桌面与 Web 通用）
  ///
  /// [fileName] 用于书名兜底推导
  static Future<({String title, String? author, List<ParsedChapter> chapters})>
      parseBytes(Uint8List bytes, {String? bookTitle, required String fileName}) async {
    final document = await PdfDocument.openData(bytes);

    try {
      final buffer = StringBuffer();

      // 逐页抽取文本
      for (var i = 0; i < document.pages.length; i++) {
        final page = document.pages[i];
        try {
          final pageText = await page.loadText();
          final text = pageText.fullText.trim();
          if (text.isNotEmpty) {
            buffer.writeln(text);
            buffer.writeln();
          }
        } catch (_) {
          // 单页抽取失败时跳过,继续后续页
        }
      }

      final fullText = buffer.toString().trim();

      // 扫描版 PDF 判定:全部页面都抽不出文字
      if (fullText.isEmpty) {
        throw PdfImportException(
          '该 PDF 为扫描图片版,无法提取文字内容。\n'
          '请使用文字版 PDF,或先用 OCR 工具转换为文本。',
        );
      }

      // 复用章节解析器切分章节
      final title = bookTitle ?? _titleFromName(fileName);
      final chapters = ChapterParser.parseChapters(fullText, bookTitle: title);

      // pdfrx 不暴露文档元数据,作者无法从 PDF 自动获取
      return (title: title, author: null, chapters: chapters);
    } finally {
      await document.dispose();
    }
  }

  /// 从文件名推导书名(去扩展名、清理分隔符)
  static String _titleFromName(String name) {
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    return nameWithoutExt.replaceAll(RegExp(r'[_\-]'), ' ').trim();
  }
}

/// PDF 导入异常
class PdfImportException implements Exception {
  final String message;
  PdfImportException(this.message);

  @override
  String toString() => message;
}
