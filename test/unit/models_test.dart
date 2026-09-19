import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/models/book.dart';
import 'package:novelmgt_flutter/models/chapter.dart';
import 'package:novelmgt_flutter/models/bookmark.dart';
import 'package:novelmgt_flutter/models/note.dart';
import 'package:novelmgt_flutter/models/reading_progress.dart';
import 'package:novelmgt_flutter/models/app_settings.dart';
import 'package:novelmgt_flutter/models/import_result.dart';

void main() {
  group('Book', () {
    test('creates with defaults', () {
      const book = Book(
        title: '测试小说',
        author: '测试作者',
        summary: '这是一本测试小说',
        status: '连载中',
        createdAt: '2024-01-01T00:00:00',
        updatedAt: '2024-01-01T00:00:00',
      );
      expect(book.title, '测试小说');
      expect(book.author, '测试作者');
      expect(book.status, '连载中');
      expect(book.id, isNull);
      expect(book.wordCount, 0);
      expect(book.rating, 0);
      expect(book.tags, isEmpty);
    });

    test('copyWith works correctly', () {
      const book = Book(
        title: '旧标题',
        author: '旧作者',
        status: '连载中',
        createdAt: '2024-01-01T00:00:00',
        updatedAt: '2024-01-01T00:00:00',
      );
      final updated = book.copyWith(title: '新标题', status: '已完结');
      expect(updated.title, '新标题');
      expect(updated.author, '旧作者');
      expect(updated.status, '已完结');
    });

    test('toJson/fromJson round-trip', () {
      const book = Book(
        id: 1,
        title: '测试',
        author: '作者',
        summary: '简介',
        status: '连载中',
        wordCount: 1000,
        rating: 4,
        createdAt: '2024-01-01',
        updatedAt: '2024-01-02',
      );
      final json = book.toJson();
      final fromJson = Book.fromJson(json);
      expect(fromJson.id, 1);
      expect(fromJson.title, '测试');
      expect(fromJson.wordCount, 1000);
      expect(fromJson.rating, 4);
    });

    test('Tag creation and JSON', () {
      const tag = Tag(id: 1, name: '玄幻', color: '#FF5722');
      final json = tag.toJson();
      final fromJson = Tag.fromJson(json);
      expect(fromJson.id, 1);
      expect(fromJson.name, '玄幻');
      expect(fromJson.color, '#FF5722');
    });
  });

  group('Chapter', () {
    test('creates with required fields', () {
      const chapter = Chapter(
        bookId: 1,
        chapterNumber: 1,
        title: '第一章',
        content: '内容...',
        createdAt: '2024-01-01',
        updatedAt: '2024-01-01',
      );
      expect(chapter.bookId, 1);
      expect(chapter.chapterNumber, 1);
      expect(chapter.title, '第一章');
      expect(chapter.id, isNull);
    });

    test('copyWith works correctly', () {
      const chapter = Chapter(
        id: 1,
        bookId: 1,
        chapterNumber: 1,
        title: '第一章',
        content: '旧内容',
        createdAt: '2024-01-01',
        updatedAt: '2024-01-01',
      );
      final updated = chapter.copyWith(title: '修改后的标题', content: '新内容');
      expect(updated.title, '修改后的标题');
      expect(updated.content, '新内容');
      expect(updated.id, 1);
      expect(updated.bookId, 1);
    });

    test('toJson/fromJson round-trip', () {
      const chapter = Chapter(
        id: 5,
        bookId: 2,
        chapterNumber: 10,
        title: '第十话',
        content: '正文内容',
        sourceUrl: 'https://example.com/ch10',
        originalOrder: 10,
        createdAt: '2024-03-01',
        updatedAt: '2024-03-01',
      );
      final json = chapter.toJson();
      final restored = Chapter.fromJson(json);
      expect(restored.id, 5);
      expect(restored.bookId, 2);
      expect(restored.chapterNumber, 10);
      expect(restored.sourceUrl, 'https://example.com/ch10');
    });
  });

  group('Bookmark', () {
    test('creates with required fields', () {
      const bookmark = Bookmark(
        bookId: 1,
        chapterId: 5,
        position: 100,
        title: '我的书签',
        createdAt: '2024-01-01',
      );
      expect(bookmark.bookId, 1);
      expect(bookmark.chapterId, 5);
      expect(bookmark.position, 100);
      expect(bookmark.note, isNull);
    });

    test('copyWith works with non-DB fields', () {
      const bookmark = Bookmark(
        id: 1,
        bookId: 1,
        chapterId: 5,
        position: 100,
        title: '书签',
        createdAt: '2024-01-01',
        chapterNumber: 5,
        chapterTitle: '第五章',
      );
      final updated = bookmark.copyWith(note: '这是书签备注');
      expect(updated.note, '这是书签备注');
      expect(updated.chapterNumber, 5);
      expect(updated.chapterTitle, '第五章');
    });
  });

  group('Note', () {
    test('creates with required fields', () {
      const note = Note(
        bookId: 1,
        chapterId: 3,
        content: '这是我的笔记',
        createdAt: '2024-01-01',
        updatedAt: '2024-01-01',
      );
      expect(note.content, '这是我的笔记');
      expect(note.position, 0);
    });

    test('copyWith works correctly', () {
      const note = Note(
        id: 1,
        bookId: 1,
        chapterId: 3,
        content: '旧笔记',
        createdAt: '2024-01-01',
        updatedAt: '2024-01-01',
        chapterNumber: 3,
        chapterTitle: '第三章',
      );
      final updated = note.copyWith(content: '新笔记');
      expect(updated.content, '新笔记');
      expect(updated.chapterNumber, 3);
    });
  });

  group('ReadingProgress', () {
    test('creates with required fields', () {
      const progress = ReadingProgress(
        bookId: 1,
        chapterId: 10,
        createdAt: '2024-01-01',
      );
      expect(progress.bookId, 1);
      expect(progress.chapterId, 10);
      expect(progress.scrollPosition, 0);
    });

    test('copyWith preserves non-DB fields', () {
      const progress = ReadingProgress(
        id: 1,
        bookId: 1,
        chapterId: 10,
        scrollPosition: 500,
        lastReadAt: '2024-03-01',
        createdAt: '2024-01-01',
        chapterNumber: 10,
        chapterTitle: '第十章',
      );
      final updated = progress.copyWith(scrollPosition: 750);
      expect(updated.scrollPosition, 750);
      expect(updated.chapterNumber, 10);
      expect(updated.chapterTitle, '第十章');
    });
  });

  group('AppSettings', () {
    test('default values are correct', () {
      const settings = AppSettings();
      expect(settings.themeMode, 'system');
      expect(settings.fontSize, 18.0);
      expect(settings.marginSize, 60.0);
      expect(settings.lineHeight, 1.8);
      expect(settings.defaultExportFormat, 'txt');
      expect(settings.autoBackup, true);
      expect(settings.backupKeepCount, 7);
    });

    test('copyWith works correctly', () {
      const settings = AppSettings();
      final updated = settings.copyWith(
        fontSize: 22.0,
        themeMode: 'dark',
        autoBackup: false,
      );
      expect(updated.fontSize, 22.0);
      expect(updated.themeMode, 'dark');
      expect(updated.autoBackup, false);
      expect(updated.marginSize, 60.0); // preserved
    });

    test('toJson/fromJson round-trip', () {
      const settings = AppSettings(
        themeMode: 'light',
        fontSize: 20.0,
        marginSize: 80.0,
        lineHeight: 2.0,
      );
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.themeMode, 'light');
      expect(restored.fontSize, 20.0);
      expect(restored.marginSize, 80.0);
      expect(restored.lineHeight, 2.0);
    });
  });

  group('ImportResult', () {
    test('success factory', () {
      final result = ImportResult.success(
        message: '导入成功',
        bookId: 1,
        bookTitle: '测试小说',
        chapterCount: 100,
      );
      expect(result.success, true);
      expect(result.bookId, 1);
      expect(result.chapterCount, 100);
    });

    test('failure factory', () {
      final result = ImportResult.failure('文件不存在');
      expect(result.success, false);
      expect(result.message, '文件不存在');
      expect(result.bookId, isNull);
    });
  });

  group('BatchImportResult', () {
    test('copyWith works correctly', () {
      const result = BatchImportResult(total: 10, succeeded: 8, failed: 1, skipped: 1);
      final updated = result.copyWith(succeeded: 9, failed: 0);
      expect(updated.succeeded, 9);
      expect(updated.failed, 0);
      expect(updated.total, 10); // preserved
    });
  });

  group('LibraryStats', () {
    test('default values', () {
      const stats = LibraryStats();
      expect(stats.totalBooks, 0);
      expect(stats.totalChapters, 0);
      expect(stats.totalWords, 0);
      expect(stats.recentlyRead, isEmpty);
    });
  });
}