// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Note _$NoteFromJson(Map<String, dynamic> json) => Note(
  id: (json['id'] as num?)?.toInt(),
  bookId: (json['bookId'] as num).toInt(),
  chapterId: (json['chapterId'] as num).toInt(),
  position: (json['position'] as num?)?.toInt() ?? 0,
  content: json['content'] as String,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
  chapterNumber: (json['chapterNumber'] as num?)?.toInt(),
  chapterTitle: json['chapterTitle'] as String?,
);

Map<String, dynamic> _$NoteToJson(Note instance) => <String, dynamic>{
  'id': instance.id,
  'bookId': instance.bookId,
  'chapterId': instance.chapterId,
  'position': instance.position,
  'content': instance.content,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
  'chapterNumber': instance.chapterNumber,
  'chapterTitle': instance.chapterTitle,
};
