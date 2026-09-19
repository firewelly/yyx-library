import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/models/models.dart';
import 'package:novelmgt_flutter/services/database_service.dart';
import 'package:novelmgt_flutter/utils/content_codec.dart';

import 'import_service_test.dart' as helper show createTestDbPublic;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContentCodec 编解码', () {
    test('小文本保持明文', () {
      final encoded = ContentCodec.encode('短章节内容');
      expect(encoded, isA<String>());
      expect(ContentCodec.decode(encoded), '短章节内容');
    });

    test('大文本压缩为 gzip blob 且往返一致', () {
      final big = '这是一段用来测试压缩的中文内容。' * 1000; // 约 16000 字符
      final encoded = ContentCodec.encode(big);
      expect(encoded, isA<Uint8List>());
      final blob = encoded as Uint8List;
      expect(blob[0], 0x1F); // gzip 魔数
      expect(blob[1], 0x8B);
      expect(blob.length, lessThan(big.length)); // 确实变小
      expect(ContentCodec.decode(encoded), big);
    });

    test('旧明文字符串数据兼容解码', () {
      expect(ContentCodec.decode('旧版本存入的明文'), '旧版本存入的明文');
    });
  });

  group('数据库压缩存储集成', () {
    late DatabaseService dbService;

    setUpAll(() async {
      dbService = await helper.createTestDbPublic();
    });

    test('大章节写入后可读回（压缩往返）', () async {
      final book = await dbService.createBook(Book(
        title: '压缩测试书',
        status: '连载中',
        wordCount: 0,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final bigContent = '第十二章的正文内容，故意写得很长。' * 2000; // > 4096 字符
      final ch = await dbService.createChapter(Chapter(
        bookId: book.id!,
        chapterNumber: 12,
        originalOrder: 12,
        title: '第十二章',
        content: bigContent,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      // 单章读取
      expect(await dbService.getChapterContent(ch.id!), bigContent);

      // 列表读取
      final chapters = await dbService.getChapters(book.id!);
      expect(chapters.first.content, bigContent);

      // 全量读取
      final all = await dbService.getAllChapters(book.id!);
      expect(all.first.content, bigContent);
    });

    test('章节搜索按标题命中（内容不参与检索）', () async {
      final book = await dbService.createBook(Book(
        title: '搜索测试书',
        status: '连载中',
        wordCount: 0,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));
      const marker = '绝无仅有的搜索密语玄黄';
      final bigContent = '${'正文铺垫。' * 2000}$marker结尾。';
      await dbService.createChapter(Chapter(
        bookId: book.id!,
        chapterNumber: 1,
        originalOrder: 1,
        title: '第一章 初入玄黄界',
        content: bigContent,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      // 标题命中
      final hits = await dbService.searchChapters(book.id!, '玄黄');
      expect(hits, isNotEmpty);
      expect(hits.first['title'], contains('玄黄'));

      // 只在内容里出现的词不再命中
      final contentHits = await dbService.searchChapters(book.id!, '搜索密语');
      expect(contentHits, isEmpty);

      // 书籍级搜索也能通过章节标题命中到书
      final books = await dbService.searchBooks('初入玄黄界', searchContent: true);
      expect(books.map((b) => b.id), contains(book.id));
    });

    test('updateChapterContent 新语义：0 无变化 / >0 旧长度', () async {
      final book = await dbService.createBook(Book(
        title: '更新测试书',
        status: '连载中',
        wordCount: 0,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));
      final ch = await dbService.createChapter(Chapter(
        bookId: book.id!,
        chapterNumber: 1,
        originalOrder: 1,
        title: '第一章',
        content: '甲' * 5000,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      expect(await dbService.updateChapterContent(ch.id!, '甲' * 5000), 0);
      expect(await dbService.updateChapterContent(ch.id!, '乙' * 3000), 5000);
    });
  });
}
