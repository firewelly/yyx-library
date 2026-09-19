// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmark.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Bookmark _$BookmarkFromJson(Map<String, dynamic> json) => Bookmark(
  id: (json['id'] as num?)?.toInt(),
  bookId: (json['bookId'] as num).toInt(),
  chapterId: (json['chapterId'] as num).toInt(),
  position: (json['position'] as num?)?.toInt() ?? 0,
  title: json['title'] as String?,
  note: json['note'] as String?,
  createdAt: json['createdAt'] as String,
  chapterNumber: (json['chapterNumber'] as num?)?.toInt(),
  chapterTitle: json['chapterTitle'] as String?,
);

Map<String, dynamic> _$BookmarkToJson(Bookmark instance) => <String, dynamic>{
  'id': instance.id,
  'bookId': instance.bookId,
  'chapterId': instance.chapterId,
  'position': instance.position,
  'title': instance.title,
  'note': instance.note,
  'createdAt': instance.createdAt,
  'chapterNumber': instance.chapterNumber,
  'chapterTitle': instance.chapterTitle,
};
