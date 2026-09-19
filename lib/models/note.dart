import 'package:json_annotation/json_annotation.dart';

part 'note.g.dart';

/// 笔记模型
@JsonSerializable()
class Note {
  final int? id;
  final int bookId;
  final int chapterId;
  final int position; // 字符偏移
  final String content;
  final String createdAt;
  final String updatedAt;

  /// 非数据库字段：由 Provider 层 JOIN 填充
  final int? chapterNumber;
  final String? chapterTitle;

  const Note({
    this.id,
    required this.bookId,
    required this.chapterId,
    this.position = 0,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.chapterNumber,
    this.chapterTitle,
  });

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
  Map<String, dynamic> toJson() => _$NoteToJson(this);

  Note copyWith({
    int? id,
    int? bookId,
    int? chapterId,
    int? position,
    String? content,
    String? createdAt,
    String? updatedAt,
    int? chapterNumber,
    String? chapterTitle,
  }) {
    return Note(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterId: chapterId ?? this.chapterId,
      position: position ?? this.position,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      chapterTitle: chapterTitle ?? this.chapterTitle,
    );
  }
}