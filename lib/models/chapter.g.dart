// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Chapter _$ChapterFromJson(Map<String, dynamic> json) => Chapter(
  id: (json['id'] as num?)?.toInt(),
  bookId: (json['bookId'] as num).toInt(),
  chapterNumber: (json['chapterNumber'] as num).toInt(),
  originalOrder: (json['originalOrder'] as num?)?.toInt(),
  title: json['title'] as String,
  content: json['content'] as String,
  sourceUrl: json['sourceUrl'] as String?,
  sourceFormat: json['sourceFormat'] as String?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, dynamic> _$ChapterToJson(Chapter instance) => <String, dynamic>{
  'id': instance.id,
  'bookId': instance.bookId,
  'chapterNumber': instance.chapterNumber,
  'originalOrder': instance.originalOrder,
  'title': instance.title,
  'content': instance.content,
  'sourceUrl': instance.sourceUrl,
  'sourceFormat': instance.sourceFormat,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
};
