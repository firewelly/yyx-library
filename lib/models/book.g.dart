// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Book _$BookFromJson(Map<String, dynamic> json) => Book(
  id: (json['id'] as num?)?.toInt(),
  title: json['title'] as String,
  author: json['author'] as String?,
  summary: json['summary'] as String?,
  status: json['status'] as String? ?? '连载中',
  sourceUrl: json['sourceUrl'] as String?,
  sourceFormat: json['sourceFormat'] as String?,
  filePath: json['filePath'] as String?,
  coverImage: json['coverImage'] as String?,
  coverImagePath: json['coverImagePath'] as String?,
  rating: (json['rating'] as num?)?.toInt() ?? 0,
  notes: json['notes'] as String?,
  wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
  lastReadAt: json['lastReadAt'] as String?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
  tags:
      (json['tags'] as List<dynamic>?)
          ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$BookToJson(Book instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'author': instance.author,
  'summary': instance.summary,
  'status': instance.status,
  'sourceUrl': instance.sourceUrl,
  'sourceFormat': instance.sourceFormat,
  'filePath': instance.filePath,
  'coverImage': instance.coverImage,
  'coverImagePath': instance.coverImagePath,
  'rating': instance.rating,
  'notes': instance.notes,
  'wordCount': instance.wordCount,
  'lastReadAt': instance.lastReadAt,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
  'tags': instance.tags.map((e) => e.toJson()).toList(),
};

Tag _$TagFromJson(Map<String, dynamic> json) => Tag(
  id: (json['id'] as num?)?.toInt(),
  name: json['name'] as String,
  color: json['color'] as String? ?? '#1976D2',
);

Map<String, dynamic> _$TagToJson(Tag instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'color': instance.color,
};
