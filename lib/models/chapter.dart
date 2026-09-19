import 'package:json_annotation/json_annotation.dart';

part 'chapter.g.dart';

/// 章节模型
@JsonSerializable()
class Chapter {
  final int? id;
  final int bookId;
  final int chapterNumber;
  final int? originalOrder;
  final String title;
  final String content;
  final String? sourceUrl;
  /// 来源格式:'txt' / 'epub' / 'pdf' / 'mobi'(可空,向后兼容旧数据)
  final String? sourceFormat;
  final String createdAt;
  final String updatedAt;

  const Chapter({
    this.id,
    required this.bookId,
    required this.chapterNumber,
    this.originalOrder,
    required this.title,
    required this.content,
    this.sourceUrl,
    this.sourceFormat,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) =>
      _$ChapterFromJson(json);
  Map<String, dynamic> toJson() => _$ChapterToJson(this);

  Chapter copyWith({
    int? id,
    int? bookId,
    int? chapterNumber,
    int? originalOrder,
    String? title,
    String? content,
    String? sourceUrl,
    String? sourceFormat,
    String? createdAt,
    String? updatedAt,
  }) {
    return Chapter(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      originalOrder: originalOrder ?? this.originalOrder,
      title: title ?? this.title,
      content: content ?? this.content,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceFormat: sourceFormat ?? this.sourceFormat,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}