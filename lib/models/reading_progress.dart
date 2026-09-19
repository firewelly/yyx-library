import 'package:json_annotation/json_annotation.dart';

part 'reading_progress.g.dart';

/// 阅读进度模型
@JsonSerializable()
class ReadingProgress {
  final int? id;
  final int bookId;
  final int chapterId;
  final int scrollPosition; // 滚动位置
  final String? lastReadAt; // ISO8601
  final String createdAt;

  /// 非数据库字段：由 Provider 层填充
  final int? chapterNumber;
  final String? chapterTitle;

  const ReadingProgress({
    this.id,
    required this.bookId,
    required this.chapterId,
    this.scrollPosition = 0,
    this.lastReadAt,
    required this.createdAt,
    this.chapterNumber,
    this.chapterTitle,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      _$ReadingProgressFromJson(json);
  Map<String, dynamic> toJson() => _$ReadingProgressToJson(this);

  ReadingProgress copyWith({
    int? id,
    int? bookId,
    int? chapterId,
    int? scrollPosition,
    String? lastReadAt,
    String? createdAt,
    int? chapterNumber,
    String? chapterTitle,
  }) {
    return ReadingProgress(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterId: chapterId ?? this.chapterId,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      createdAt: createdAt ?? this.createdAt,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      chapterTitle: chapterTitle ?? this.chapterTitle,
    );
  }
}