import 'package:json_annotation/json_annotation.dart';

part 'bookmark.g.dart';

/// 书签模型
@JsonSerializable()
class Bookmark {
  final int? id;
  final int bookId;
  final int chapterId;
  final int position; // 字符偏移
  final String? title;
  final String? note;
  final String createdAt;

  /// 非数据库字段：由 Provider 层 JOIN 填充
  final int? chapterNumber;
  final String? chapterTitle;

  const Bookmark({
    this.id,
    required this.bookId,
    required this.chapterId,
    this.position = 0,
    this.title,
    this.note,
    required this.createdAt,
    this.chapterNumber,
    this.chapterTitle,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) =>
      _$BookmarkFromJson(json);
  Map<String, dynamic> toJson() => _$BookmarkToJson(this);

  Bookmark copyWith({
    int? id,
    int? bookId,
    int? chapterId,
    int? position,
    String? title,
    String? note,
    String? createdAt,
    int? chapterNumber,
    String? chapterTitle,
  }) {
    return Bookmark(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterId: chapterId ?? this.chapterId,
      position: position ?? this.position,
      title: title ?? this.title,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      chapterTitle: chapterTitle ?? this.chapterTitle,
    );
  }
}