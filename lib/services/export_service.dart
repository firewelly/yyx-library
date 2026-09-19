import 'dart:convert';
import 'dart:typed_data';
import 'package:epubx/epubx.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'database_service.dart';
import 'platform_fs.dart';
import '../utils/web_launcher.dart';

/// 导出服务 - TXT/EPUB/PDF/MOBI 导出
///
/// 分两层：
/// - 生成层（buildXxxBytes）：从数据库生成文件字节，纯 Dart，桌面/Web 通用
/// - 输出层：桌面端写入指定目录（PlatformFs）；Web 端触发浏览器下载
///   （[exportDownload]，无目录概念）
class ExportService {
  final DatabaseService _db;

  ExportService(this._db);

  /// 导出书籍为 TXT 格式（桌面端：写入 [outputDir]）
  Future<String> exportToTxt(int bookId, String outputDir) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final bytes = await buildTxtBytes(bookId);
    final fileName = _sanitizeFileName(book.title);
    return PlatformFs.writeTextFile(outputDir, '$fileName.txt', utf8.decode(bytes));
  }

  /// 导出书籍为 EPUB 格式（桌面端：写入 [outputDir]）
  Future<String> exportToEpub(int bookId, String outputDir) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final bytes = await buildEpubBytes(bookId);
    final fileName = _sanitizeFileName(book.title);
    return PlatformFs.writeBytesFile(outputDir, '$fileName.epub', bytes);
  }

  /// 导出书籍为 PDF 格式（桌面端：写入 [outputDir]）
  ///
  /// 生成封面页(书名/作者/简介)+ 每章自动分页、章节标题、正文、页码。
  Future<String> exportToPdf(int bookId, String outputDir) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final bytes = await buildPdfBytes(bookId);
    final fileName = _sanitizeFileName(book.title);
    return PlatformFs.writeBytesFile(outputDir, '$fileName.pdf', bytes);
  }

  /// 导出书籍为 MOBI/Kindle 兼容格式（桌面端：写入 [outputDir]）
  ///
  /// 纯 Dart 生态无成熟的 MOBI 写入器,故以 EPUB 格式输出(Kindle 设备与
  /// Send-to-Kindle 均可直接读取 EPUB),并在文件名后缀标注。
  /// 返回值 filePath 为实际生成的 .epub 路径。
  Future<String> exportToMobi(int bookId, String outputDir) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final bytes = await buildEpubBytes(bookId);
    final fileName = _sanitizeFileName(book.title);
    return PlatformFs.writeBytesFile(outputDir, '${fileName}_kindle.epub', bytes);
  }

  /// 按格式名称统一导出入口（桌面端）
  Future<String> export(int bookId, String outputDir, String format) async {
    switch (format.toLowerCase()) {
      case 'txt':
        return exportToTxt(bookId, outputDir);
      case 'epub':
        return exportToEpub(bookId, outputDir);
      case 'pdf':
        return exportToPdf(bookId, outputDir);
      case 'mobi':
      case 'kindle':
        return exportToMobi(bookId, outputDir);
      default:
        throw ArgumentError('不支持的导出格式: $format');
    }
  }

  /// Web 端导出：生成字节并触发浏览器下载，返回下载文件名。
  ///
  /// Web 无目录概念，不需要用户选择导出目录。
  Future<String> exportDownload(int bookId, String format) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final base = _sanitizeFileName(book.title);
    final fmt = format.toLowerCase();
    final (bytes, ext, mime) = switch (fmt) {
      'txt' => (await buildTxtBytes(bookId), 'txt', 'text/plain'),
      'epub' => (await buildEpubBytes(bookId), 'epub', 'application/epub+zip'),
      'pdf' => (await buildPdfBytes(bookId), 'pdf', 'application/pdf'),
      'mobi' || 'kindle' => (
          await buildEpubBytes(bookId),
          'epub',
          'application/epub+zip'
        ),
      _ => throw ArgumentError('不支持的导出格式: $format'),
    };

    final fileName = fmt == 'mobi' || fmt == 'kindle'
        ? '${base}_kindle.$ext'
        : '$base.$ext';
    await WebLauncher.downloadBytes(fileName, bytes, mimeType: mime);
    return fileName;
  }

  // ============================================================
  // 生成层：以下方法只依赖数据库，输出内存字节（桌面/Web 通用）
  // ============================================================

  /// 生成 TXT 内容字节
  Future<Uint8List> buildTxtBytes(int bookId) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final chapters = await _db.getAllChapters(bookId);

    // 构建文本内容
    final buffer = StringBuffer();
    buffer.writeln(book.title);
    if (book.author != null && book.author!.isNotEmpty) {
      buffer.writeln('作者: ${book.author}');
    }
    if (book.summary != null && book.summary!.isNotEmpty) {
      buffer.writeln('简介: ${book.summary}');
    }
    buffer.writeln('状态: ${book.status}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (final chapter in chapters) {
      buffer.writeln('第${chapter.chapterNumber}章 ${chapter.title}');
      buffer.writeln('-' * 30);
      buffer.writeln(chapter.content);
      buffer.writeln();
      buffer.writeln();
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  /// 生成 EPUB 文件字节
  Future<Uint8List> buildEpubBytes(int bookId) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final chapters = await _db.getAllChapters(bookId);

    // 构建 EPUB 内容
    final epubBook = EpubBook();

    // 元数据
    epubBook.Title = book.title;
    epubBook.Author = book.author ?? '未知作者';

    // 构建 Schema.Package
    final package = EpubPackage();
    final metadata = EpubMetadata();
    metadata.Titles = [book.title];
    final creator = EpubMetadataCreator();
    creator.Creator = book.author ?? '未知作者';
    creator.Role = 'aut';
    metadata.Creators = [creator];
    metadata.Description = book.summary ?? '';
    package.Metadata = metadata;

    // 创建 HTML 文件和 manifest/spine 条目
    final htmlFiles = <String, EpubTextContentFile>{};
    final manifestItems = <EpubManifestItem>[];
    final spineItemRefs = <EpubSpineItemRef>[];

    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final chapterId = 'chapter_${i + 1}';
      final htmlContent = _buildChapterHtml(chapter.title, chapter.content);

      final htmlFile = EpubTextContentFile();
      htmlFile.Content = htmlContent;
      htmlFile.FileName = '$chapterId.xhtml';
      htmlFile.ContentMimeType = 'application/xhtml+xml';
      htmlFile.ContentType = EpubContentType.XHTML_1_1;
      htmlFiles[chapterId] = htmlFile;

      final manifestItem = EpubManifestItem();
      manifestItem.Id = chapterId;
      manifestItem.Href = '$chapterId.xhtml';
      manifestItem.MediaType = 'application/xhtml+xml';
      manifestItems.add(manifestItem);

      final spineItemRef = EpubSpineItemRef();
      spineItemRef.IdRef = chapterId;
      spineItemRef.IsLinear = true;
      spineItemRefs.add(spineItemRef);
    }

    // 设置内容
    final content = EpubContent();
    content.Html = htmlFiles;
    content.AllFiles = Map<String, EpubContentFile>.from(htmlFiles);
    epubBook.Content = content;

    // 设置 Manifest 和 Spine
    final manifest = EpubManifest();
    manifest.Items = manifestItems;
    package.Manifest = manifest;

    final spine = EpubSpine();
    spine.Items = spineItemRefs;
    spine.ltr = true;
    package.Spine = spine;

    // 设置 Schema
    final schema = EpubSchema();
    schema.ContentDirectoryPath = 'OEBPS';
    schema.Package = package;
    epubBook.Schema = schema;

    final bytes = EpubWriter.writeBook(epubBook);
    if (bytes == null) {
      throw Exception('EPUB 生成失败');
    }
    return Uint8List.fromList(bytes);
  }

  /// 生成 PDF 文件字节
  Future<Uint8List> buildPdfBytes(int bookId) async {
    final book = await _db.getBook(bookId);
    if (book == null) throw ArgumentError('Book not found: $bookId');

    final chapters = await _db.getAllChapters(bookId);

    final pdf = pw.Document();

    // 封面页
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                book.title,
                style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              if (book.author != null && book.author!.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text(
                  book.author!,
                  style: const pw.TextStyle(fontSize: 16, color: PdfColors.grey700),
                ),
              ],
              if (book.summary != null && book.summary!.isNotEmpty) ...[
                pw.SizedBox(height: 32),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                  child: pw.Text(
                    book.summary!,
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // 各章内容(使用 MultiPage 自动分页)
    for (final chapter in chapters) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(48),
          header: (context) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              book.title,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ),
          footer: (context) => pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ),
          build: (context) => [
            pw.Header(
              level: 1,
              text: '第${chapter.chapterNumber}章 ${chapter.title}',
            ),
            pw.SizedBox(height: 12),
            pw.Paragraph(
              text: chapter.content,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
            ),
            pw.SizedBox(height: 24),
          ],
        ),
      );
    }

    return pdf.save();
  }

  /// 构建章节 HTML 内容
  String _buildChapterHtml(String title, String content) {
    // 转义 HTML 特殊字符
    final escapedContent = content
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br/>\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$title</title></head>
<body>
<h1>$title</h1>
<div>$escapedContent</div>
</body>
</html>''';
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }
}
