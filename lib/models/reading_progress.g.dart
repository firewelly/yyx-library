// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReadingProgress _$ReadingProgressFromJson(Map<String, dynamic> json) =>
    ReadingProgress(
      id: (json['id'] as num?)?.toInt(),
      bookId: (json['bookId'] as num).toInt(),
      chapterId: (json['chapterId'] as num).toInt(),
      scrollPosition: (json['scrollPosition'] as num?)?.toInt() ?? 0,
      lastReadAt: json['lastReadAt'] as String?,
      createdAt: json['createdAt'] as String,
      chapterNumber: (json['chapterNumber'] as num?)?.toInt(),
      chapterTitle: json['chapterTitle'] as String?,
    );

Map<String, dynamic> _$ReadingProgressToJson(ReadingProgress instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bookId': instance.bookId,
      'chapterId': instance.chapterId,
      'scrollPosition': instance.scrollPosition,
      'lastReadAt': instance.lastReadAt,
      'createdAt': instance.createdAt,
      'chapterNumber': instance.chapterNumber,
      'chapterTitle': instance.chapterTitle,
    };
