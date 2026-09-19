import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:epubx/epubx.dart';
import '../models/models.dart';
import '../utils/html_text.dart';
import '../utils/text_decode.dart';
import '../utils/book_path.dart';
import 'chapter_parser.dart';
import 'database_service.dart';
import 'pdf_importer.dart';
import 'mobi_importer.dart';
import 'platform_fs.dart';

/// 支持导入的文件扩展名
const List<String> kSupportedImportExtensions = [
  '.txt',
  '.epub',
  '.pdf',
  '.mobi',
  '.azw',
  '.azw3',
];

/// 导入服务 - TXT/EPUB/PDF/MOBI 文件导入，支持章节更新检测
class ImportService {
  final DatabaseService _db;

  /// 书库根目录取值器（跨系统共享数据库时，filePath 存为相对该目录的路径）。
  /// 为空或未提供时 filePath 按原样存储。
  final String Function()? pathBase;

  ImportService(this._db, {this.pathBase});

  /// 当前生效的书库根目录：显式配置优先，否则以程序目录为基准
  /// （便携部署：程序与 novels/、H/ 同级时无需任何配置，路径自动存相对形式）
  String get _libraryRoot => PlatformFs.effectiveLibraryRoot(pathBase?.call() ?? '');

  /// 导入 TXT 文件（桌面端路径入口）
  Future<ImportResult> importTxtFile(
    String filePath, {
    String? author,
    List<String>? tags,
    String encoding = 'auto',
  }) async {
    try {
      final bytes = await PlatformFs.readBytes(filePath);
      if (bytes == null) {
        return ImportResult.failure('文件不存在: $filePath');
      }
      return await importTxtBytes(
        p.basename(filePath),
        bytes,
        author: author,
        tags: tags,
        sourcePath: filePath,
        encoding: encoding,
      );
    } catch (e) {
      return ImportResult.failure('导入失败: $e');
    }
  }

  /// 导入内存中的 TXT 字节（桌面与 Web 通用）
  ///
  /// [fileName] 用于书名推导与来源记录；[encoding] 见 [TextDecode.decode]
  Future<ImportResult> importTxtBytes(
    String fileName,
    Uint8List bytes, {
    String? author,
    List<String>? tags,
    String? sourcePath,
    String encoding = 'auto',
  }) async {
    try {
      // 大文件防护：导入链路为整本解析，超大文件内存峰值会数倍于文件体积。
      // Web 端受浏览器堆限制更严格（SQLite WASM 也在同一进程内）。
      const webLimitMb = 30;
      const desktopLimitMb = 100;
      const limitMb = kIsWeb ? webLimitMb : desktopLimitMb;
      if (bytes.lengthInBytes > limitMb * 1024 * 1024) {
        final sizeMb = (bytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1);
        return ImportResult.failure(
          '文件过大（${sizeMb}MB），超过${kIsWeb ? 'Web 端' : '桌面端'} ${limitMb}MB 上限'
          '${kIsWeb ? '，请使用桌面端导入' : ''}',
        );
      }
      // 读取文件并检测编码
      String content;
      try {
        // 编码：手动指定（设置页默认编码）或自动探测 UTF-8→GBK→Big5
        content = await TextDecode.decode(bytes, encoding: encoding);
      } catch (e) {
        return ImportResult.failure('编码检测失败: $e');
      }

      // 从文件名提取书名（去掉扩展名）
      final bookTitle = p.basenameWithoutExtension(fileName).replaceAll(RegExp(r'[_\-]'), ' ').trim();

      // 解析章节
      final chapters = ChapterParser.parseChapters(content, bookTitle: bookTitle);
      final totalWords = content.length;

      // 检查是否已存在同标题同作者的书
      final existingBook = await _db.findBookByTitleAndAuthor(bookTitle, author: author);

      if (existingBook != null) {
        // 书籍已存在，检查章节更新
        return await _updateExistingBook(existingBook, chapters);
      }

      // 创建新书籍及其章节（事务保护：失败自动回滚）
      return await _createBookWithChapters(
        title: bookTitle,
        author: author,
        wordCount: totalWords,
        sourceFormat: 'txt',
        chapters: chapters,
        tags: tags,
        filePath: sourcePath ?? fileName,
      );
    } catch (e) {
      return ImportResult.failure('导入失败: $e');
    }
  }

  /// 更新已存在的书籍（检查章节内容变化）
  Future<ImportResult> _updateExistingBook(Book existingBook, List<ParsedChapter> newChapters) async {
    // 获取现有章节
    final existingChapters = await _db.getChapterList(existingBook.id!);
    final existingByNumber = {for (var ch in existingChapters) ch.chapterNumber: ch};

    int updatedCount = 0;
    int addedCount = 0;
    // 增量重算字数：记录被更新章节的旧长度与新长度，避免全量加载章节内容
    int removedChars = 0;
    int addedChars = 0;
    final now = DateTime.now().toIso8601String();

    for (final newCh in newChapters) {
      final existing = existingByNumber[newCh.chapterNumber];
      
      if (existing != null) {
        // 章节已存在，检查内容是否更新
        // 返回值：-1 不存在 / 0 无变化 / >0 旧内容长度
        final oldLength = await _db.updateChapterContent(existing.id!, newCh.content);
        if (oldLength > 0) {
          updatedCount++;
          removedChars += oldLength;
          addedChars += newCh.content.length;
        }
      } else {
        // 新章节，添加（TXT 更新路径，来源格式固定为 txt）
        await _db.createChapter(Chapter(
          bookId: existingBook.id!,
          chapterNumber: newCh.chapterNumber,
          originalOrder: newCh.originalOrder,
          title: newCh.title,
          content: newCh.content,
          sourceFormat: 'txt',
          createdAt: now,
          updatedAt: now,
        ));
        addedCount++;
        addedChars += newCh.content.length;
      }
    }

    // 更新书籍的 updatedAt 和字数（增量计算）
    if (updatedCount > 0 || addedCount > 0) {
      await _db.touchBook(existingBook.id!);
      final totalWords = existingBook.wordCount - removedChars + addedChars;
      await _db.updateBook(existingBook.copyWith(
        wordCount: totalWords < 0 ? 0 : totalWords,
        updatedAt: now,
      ));
    }

    String message;
    if (updatedCount > 0 || addedCount > 0) {
      message = '《${existingBook.title}»已更新：新增 $addedCount 章，更新 $updatedCount 章内容';
    } else {
      message = '《${existingBook.title}»无变化，跳过';
    }

    return ImportResult.success(
      message: message,
      bookId: existingBook.id,
      bookTitle: existingBook.title,
      chapterCount: existingChapters.length + addedCount,
    );
  }

  /// 在单个事务中创建书籍及其章节。
  ///
  /// 用于新书导入路径（TXT/EPUB/PDF/MOBI 共用）：任意一步失败都会回滚，
  /// 避免数据库中残留「半本书」（已建书籍但章节未写完）。
  /// [sourceFormat] 取值为 'txt' / 'epub' / 'pdf' / 'mobi'。
  Future<ImportResult> _createBookWithChapters({
    required String title,
    required String? author,
    String? summary,
    required int wordCount,
    required String sourceFormat,
    required List<ParsedChapter> chapters,
    List<String>? tags,
    String? filePath,
  }) async {
    try {
      final createdBook = await _db.db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        // 事务内必须用事务对象执行（executor: txn），否则外层连接等锁
        final book = await _db.createBook(Book(
          title: title,
          author: author,
          summary: summary,
          status: '连载中',
          wordCount: wordCount,
          sourceFormat: sourceFormat,
          // 跨系统共享数据库：路径存相对书库根目录的形式
          filePath: filePath == null || filePath.isEmpty
              ? null
              : BookPath.relativize(filePath, _libraryRoot),
          createdAt: now,
          updatedAt: now,
          tags: tags?.map((t) => Tag(name: t)).toList() ?? [],
        ), executor: txn);
        // 批量写入全部章节；任一异常会令整个事务回滚
        await _db.createChaptersBatch([
          for (final ch in chapters)
            Chapter(
              bookId: book.id!,
              chapterNumber: ch.chapterNumber,
              originalOrder: ch.originalOrder,
              title: ch.title,
              content: ch.content,
              sourceFormat: sourceFormat,
              createdAt: now,
              updatedAt: now,
            ),
        ], executor: txn);
        return book;
      });

      final extLabel = const {
        'txt': '',
        'epub': '',
        'pdf': '(PDF)',
        'mobi': '(Kindle)',
      }[sourceFormat] ??
          '';
      return ImportResult.success(
        message: '成功导入《$title》，共 ${chapters.length} 章$extLabel',
        bookId: createdBook.id,
        bookTitle: createdBook.title,
        chapterCount: chapters.length,
      );
    } catch (e) {
      return ImportResult.failure('导入失败（已回滚）: $e');
    }
  }

  /// 导入 EPUB 文件（桌面端路径入口）
  Future<ImportResult> importEpubFile(
    String filePath, {
    String? author,
    List<String>? tags,
  }) async {
    try {
      final bytes = await PlatformFs.readBytes(filePath);
      if (bytes == null) {
        return ImportResult.failure('文件不存在: $filePath');
      }
      return await importEpubBytes(
        p.basename(filePath),
        bytes,
        author: author,
        tags: tags,
        sourcePath: filePath,
      );
    } catch (e) {
      return ImportResult.failure('EPUB导入失败: $e');
    }
  }

  /// 导入内存中的 EPUB 字节（桌面与 Web 通用）
  Future<ImportResult> importEpubBytes(
    String fileName,
    Uint8List bytes, {
    String? author,
    List<String>? tags,
    String? sourcePath,
  }) async {
    try {
      final epubBook = await EpubReader.readBook(bytes);

      // 提取元数据
      final bookTitle = epubBook.Title ?? p.basenameWithoutExtension(fileName);
      final bookAuthor = author ?? epubBook.Author ?? '';
      final summary = epubBook.Schema?.Package?.Metadata?.Description ?? '';

      // 检查是否已存在同标题同作者的书
      final existingBook = await _db.findBookByTitleAndAuthor(bookTitle, author: bookAuthor.isNotEmpty ? bookAuthor : null);
      
      // 提取章节内容
      final chapters = <ParsedChapter>[];
      final spine = epubBook.Schema?.Package?.Spine;
      int originalOrder = 0;
      int totalWords = 0;

      if (spine != null) {
        for (final spineItem in spine.Items ?? []) {
          final htmlContent = epubBook.Content?.Html;
          if (htmlContent == null) continue;

          final htmlFile = htmlContent[spineItem.IdRef];
          if (htmlFile == null) continue;

          final contentText = _stripHtmlTags(htmlFile.Content ?? '');
          if (contentText.trim().isEmpty) continue;

          final title = htmlFile.FileName ?? '第${originalOrder + 1}章';
          final extractedNum = ChapterParser.extractChapterNumber(title);
          totalWords += contentText.length;
          originalOrder++;

          chapters.add(ParsedChapter(
            title: title,
            content: contentText,
            chapterNumber: extractedNum ?? originalOrder,
            originalOrder: originalOrder,
            extractedNumber: extractedNum,
            startLine: 0,
          ));
        }
      }

      // 按章节号排序
      // 使用解析后的章节（已排序）
      final finalChapters = List<ParsedChapter>.from(chapters);
      final withNumber = finalChapters.where((ch) => ch.extractedNumber != null && ch.extractedNumber! > 0).toList();
      final withoutNumber = finalChapters.where((ch) => ch.extractedNumber == null || ch.extractedNumber == 0).toList();
      
      withNumber.sort((a, b) => a.extractedNumber!.compareTo(b.extractedNumber!));
      withoutNumber.sort((a, b) => a.originalOrder.compareTo(b.originalOrder));
      
      final sortedList = [...withNumber, ...withoutNumber];
      for (int i = 0; i < sortedList.length; i++) {
        sortedList[i] = sortedList[i].copyWith(chapterNumber: i + 1);
      }

      if (existingBook != null) {
        // 书籍已存在，检查章节更新
        return await _updateExistingBookFromParsed(existingBook, sortedList);
      }

      // 创建新书籍及其章节（事务保护：失败自动回滚）
      return await _createBookWithChapters(
        title: bookTitle,
        author: bookAuthor,
        summary: summary.isNotEmpty ? summary : null,
        wordCount: totalWords,
        sourceFormat: 'epub',
        chapters: sortedList,
        tags: tags,
        filePath: sourcePath ?? fileName,
      );
    } catch (e) {
      return ImportResult.failure('EPUB导入失败: $e');
    }
  }

  /// 从解析的章节更新已存在的书籍
  Future<ImportResult> _updateExistingBookFromParsed(Book existingBook, List<ParsedChapter> newChapters) async {
    // 获取现有章节索引（不含内容，轻量；内容比对交给 updateChapterContent 按需加载）
    final existingChapters = await _db.getChapterList(existingBook.id!);
    final existingByNumber = {for (var ch in existingChapters) ch.chapterNumber: ch};

    int updatedCount = 0;
    int addedCount = 0;
    final now = DateTime.now().toIso8601String();

    for (final newCh in newChapters) {
      final existing = existingByNumber[newCh.chapterNumber];
      
      if (existing != null) {
        // 章节已存在，检查内容是否更新（返回值：-1 不存在 / 0 无变化 / >0 已更新）
        final oldLength = await _db.updateChapterContent(existing.id!, newCh.content);
        if (oldLength > 0) {
          updatedCount++;
        }
      } else {
        // 新章节，添加（继承书籍的来源格式，保持格式标记一致）
        await _db.createChapter(Chapter(
          bookId: existingBook.id!,
          chapterNumber: newCh.chapterNumber,
          originalOrder: newCh.originalOrder,
          title: newCh.title,
          content: newCh.content,
          sourceFormat: existingBook.sourceFormat,
          createdAt: now,
          updatedAt: now,
        ));
        addedCount++;
      }
    }

    // 更新书籍
    if (updatedCount > 0 || addedCount > 0) {
      await _db.touchBook(existingBook.id!);
      final totalWords = newChapters.fold(0, (sum, ch) => sum + ch.content.length);
      await _db.updateBook(existingBook.copyWith(wordCount: totalWords, updatedAt: now));
    }

    String message;
    if (updatedCount > 0 || addedCount > 0) {
      message = '《${existingBook.title}»已更新：新增 $addedCount 章，更新 $updatedCount 章内容';
    } else {
      message = '《${existingBook.title}»无变化，跳过';
    }

    return ImportResult.success(
      message: message,
      bookId: existingBook.id,
      bookTitle: existingBook.title,
      chapterCount: existingChapters.length + addedCount,
    );
  }

  /// 批量导入文件夹（仅桌面端：Web 无本地文件夹访问）
  Future<BatchImportResult> importFolder(
    String folderPath, {
    bool recursive = false,
    String? author,
    List<String>? tags,
    bool deleteAfterImport = false,
    String encoding = 'auto',
    void Function(int current, int total, String message)? progressCallback,
  }) async {
    if (!await PlatformFs.dirExists(folderPath)) {
      return const BatchImportResult(errors: ['文件夹不存在']);
    }

    // 收集所有支持格式的文件（跳过 0 字节文件）
    final allFiles = await PlatformFs.listFiles(
      folderPath,
      recursive: recursive,
      extensions: kSupportedImportExtensions.toSet(),
      skipZeroByte: true,
    );
    final total = allFiles.length;

    if (total == 0) {
      return const BatchImportResult(errors: ['未找到可导入的文件(TXT/EPUB/PDF/MOBI)']);
    }

    int succeeded = 0;
    int failed = 0;
    int skipped = 0;
    final errors = <String>[];
    final importedIds = <int>[];

    for (int i = 0; i < allFiles.length; i++) {
      final filePath = allFiles[i];
      progressCallback?.call(i + 1, total, '正在导入: ${p.basename(filePath)}');

      // 按扩展名自动分派到对应导入器
      final result =
          await importByExtension(filePath, author: author, tags: tags, encoding: encoding);

      if (result.success) {
        succeeded++;
        if (result.bookId != null) importedIds.add(result.bookId!);
        if (deleteAfterImport) {
          try {
            await PlatformFs.deleteFile(filePath);
          } catch (_) {}
        }
      } else if (result.message.contains('已存在')) {
        // 重复书籍，计为跳过而非失败
        skipped++;
      } else {
        failed++;
        errors.add('${p.basename(filePath)}: ${result.message}');
      }
    }

    return BatchImportResult(
      total: total,
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
      errors: errors,
      importedBookIds: importedIds,
    );
  }

  /// 导入 PDF 文件(文字版)（桌面端路径入口）
  Future<ImportResult> importPdfFile(
    String filePath, {
    String? author,
    List<String>? tags,
  }) async {
    return await importPdfBytes(
      p.basename(filePath),
      await PlatformFs.readBytes(filePath) ?? Uint8List(0),
      author: author,
      tags: tags,
      sourcePath: filePath,
    );
  }

  /// 导入内存中的 PDF 字节(文字版)（桌面与 Web 通用）
  Future<ImportResult> importPdfBytes(
    String fileName,
    Uint8List bytes, {
    String? author,
    List<String>? tags,
    String? sourcePath,
  }) async {
    try {
      if (bytes.isEmpty) {
        return ImportResult.failure('文件不存在或为空: $fileName');
      }

      final parsed = await PdfImporter.parseBytes(bytes, fileName: fileName);
      final chapters = parsed.chapters;
      final bookTitle = parsed.title;
      final bookAuthor = author ?? parsed.author;
      final totalWords = chapters.fold(0, (sum, ch) => sum + ch.content.length);

      if (chapters.isEmpty) {
        return ImportResult.failure('PDF 内容为空或无法解析');
      }

      // 检查是否已存在
      final existingBook =
          await _db.findBookByTitleAndAuthor(bookTitle, author: bookAuthor);
      if (existingBook != null) {
        return await _updateExistingBookFromParsed(existingBook, chapters);
      }

      // 创建新书籍及其章节（事务保护：失败自动回滚）
      return await _createBookWithChapters(
        title: bookTitle,
        author: bookAuthor,
        wordCount: totalWords,
        sourceFormat: 'pdf',
        chapters: chapters,
        tags: tags,
        filePath: sourcePath ?? fileName,
      );
    } on PdfImportException catch (e) {
      return ImportResult.failure(e.message);
    } catch (e) {
      return ImportResult.failure('PDF 导入失败: $e');
    }
  }

  /// 导入 MOBI / AZW / AZW3 / KF8 文件（桌面端路径入口）
  Future<ImportResult> importMobiFile(
    String filePath, {
    String? author,
    List<String>? tags,
  }) async {
    return await importMobiBytes(
      p.basename(filePath),
      await PlatformFs.readBytes(filePath) ?? Uint8List(0),
      author: author,
      tags: tags,
      sourcePath: filePath,
    );
  }

  /// 导入内存中的 MOBI/AZW/AZW3 字节（桌面与 Web 通用）
  Future<ImportResult> importMobiBytes(
    String fileName,
    Uint8List bytes, {
    String? author,
    List<String>? tags,
    String? sourcePath,
  }) async {
    try {
      if (bytes.isEmpty) {
        return ImportResult.failure('文件不存在或为空: $fileName');
      }

      final parsed = await MobiImporter.parseBytes(bytes, fileName: fileName);
      final chapters = parsed.chapters;
      final bookTitle = parsed.title;
      final bookAuthor = author ?? parsed.author;
      final totalWords = chapters.fold(0, (sum, ch) => sum + ch.content.length);

      if (chapters.isEmpty) {
        return ImportResult.failure('Kindle 文件内容为空或无法解析');
      }

      // 检查是否已存在
      final existingBook =
          await _db.findBookByTitleAndAuthor(bookTitle, author: bookAuthor);
      if (existingBook != null) {
        return await _updateExistingBookFromParsed(existingBook, chapters);
      }

      // 创建新书籍及其章节（事务保护：失败自动回滚）
      return await _createBookWithChapters(
        title: bookTitle,
        author: bookAuthor,
        wordCount: totalWords,
        sourceFormat: 'mobi',
        chapters: chapters,
        tags: tags,
        filePath: sourcePath ?? fileName,
      );
    } on MobiImportException catch (e) {
      return ImportResult.failure(e.message);
    } catch (e) {
      return ImportResult.failure('Kindle 导入失败: $e');
    }
  }

  /// 根据文件扩展名自动选择导入方法（路径版，桌面端）
  Future<ImportResult> importByExtension(
    String filePath, {
    String? author,
    List<String>? tags,
    String encoding = 'auto',
  }) async {
    final ext = filePath.toLowerCase();
    if (ext.endsWith('.txt')) {
      return importTxtFile(filePath, author: author, tags: tags, encoding: encoding);
    } else if (ext.endsWith('.epub')) {
      return importEpubFile(filePath, author: author, tags: tags);
    } else if (ext.endsWith('.pdf')) {
      return importPdfFile(filePath, author: author, tags: tags);
    } else if (ext.endsWith('.mobi') ||
        ext.endsWith('.azw') ||
        ext.endsWith('.azw3')) {
      return importMobiFile(filePath, author: author, tags: tags);
    }
    return ImportResult.failure('不支持的文件格式: $filePath');
  }

  /// 根据文件名扩展名自动选择导入方法（字节版，桌面与 Web 通用）。
  ///
  /// Web 端导入主入口：file_picker 在 Web 上只能给出文件字节（无路径），
  /// 由 [fileName] 的扩展名分派到 TXT/EPUB/PDF/MOBI 导入器。
  /// [encoding] 仅对 TXT 生效，见 [TextDecode.decode]。
  Future<ImportResult> importByBytes(
    String fileName,
    Uint8List bytes, {
    String? author,
    List<String>? tags,
    String encoding = 'auto',
  }) async {
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.txt')) {
      return await importTxtBytes(fileName, bytes, author: author, tags: tags, encoding: encoding);
    } else if (ext.endsWith('.epub')) {
      return await importEpubBytes(fileName, bytes, author: author, tags: tags);
    } else if (ext.endsWith('.pdf')) {
      return await importPdfBytes(fileName, bytes, author: author, tags: tags);
    } else if (ext.endsWith('.mobi') ||
        ext.endsWith('.azw') ||
        ext.endsWith('.azw3')) {
      return await importMobiBytes(fileName, bytes, author: author, tags: tags);
    }
    return ImportResult.failure('不支持的文件格式: $fileName');
  }

  /// 去除 HTML 标签并解码实体(与 PDF/MOBI 导入共用同一实现)
  String _stripHtmlTags(String html) {
    return HtmlText.stripHtml(html);
  }
}