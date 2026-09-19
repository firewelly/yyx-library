/// 导入结果模型
library;

import 'book.dart';

class ImportResult {
  final bool success;
  final String message;
  final int? bookId;
  final String? bookTitle;
  final int chapterCount;

  const ImportResult({
    required this.success,
    required this.message,
    this.bookId,
    this.bookTitle,
    this.chapterCount = 0,
  });

  factory ImportResult.failure(String message) =>
      ImportResult(success: false, message: message);

  factory ImportResult.success({
    required String message,
    int? bookId,
    String? bookTitle,
    int chapterCount = 0,
  }) =>
      ImportResult(
        success: true,
        message: message,
        bookId: bookId,
        bookTitle: bookTitle,
        chapterCount: chapterCount,
      );
}

/// 批量导入结果
class BatchImportResult {
  final int total;
  final int succeeded;
  final int failed;
  final int skipped;
  final List<String> errors;
  final List<int> importedBookIds;

  const BatchImportResult({
    this.total = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = 0,
    this.errors = const [],
    this.importedBookIds = const [],
  });

  BatchImportResult copyWith({
    int? total,
    int? succeeded,
    int? failed,
    int? skipped,
    List<String>? errors,
    List<int>? importedBookIds,
  }) {
    return BatchImportResult(
      total: total ?? this.total,
      succeeded: succeeded ?? this.succeeded,
      failed: failed ?? this.failed,
      skipped: skipped ?? this.skipped,
      errors: errors ?? this.errors,
      importedBookIds: importedBookIds ?? this.importedBookIds,
    );
  }
}

/// 统计数据模型
class LibraryStats {
  final int totalBooks;
  final int totalChapters;
  final int totalWords;
  final int totalAuthors;
  final int totalTags;
  final Map<String, int> statusDistribution;
  final Map<int, int> ratingDistribution;
  final List<TagCount> topTags;
  final List<AuthorCount> topAuthors;
  final List<Book> recentlyRead;

  const LibraryStats({
    this.totalBooks = 0,
    this.totalChapters = 0,
    this.totalWords = 0,
    this.totalAuthors = 0,
    this.totalTags = 0,
    this.statusDistribution = const {},
    this.ratingDistribution = const {},
    this.topTags = const [],
    this.topAuthors = const [],
    this.recentlyRead = const [],
  });
}

class TagCount {
  final String name;
  final String color;
  final int count;

  const TagCount({required this.name, this.color = '#1976D2', required this.count});
}

class AuthorCount {
  final String name;
  final int count;

  const AuthorCount({required this.name, required this.count});
}