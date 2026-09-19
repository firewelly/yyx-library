import 'package:json_annotation/json_annotation.dart';

part 'book.g.dart';

/// 书籍模型
@JsonSerializable(explicitToJson: true)
class Book {
  final int? id;
  final String title;
  final String? author;
  final String? summary;
  final String status; // '连载中', '已完结'
  final String? sourceUrl;
  /// 来源格式:'txt' / 'epub' / 'pdf' / 'mobi'(可空,向后兼容旧数据)
  final String? sourceFormat;
  /// 导入文件相对路径（本地导入时记录，爬虫入库为空）
  final String? filePath;
  final String? coverImage;
  final String? coverImagePath;
  final int rating; // 0-5
  final String? notes;
  final int wordCount;
  final String? lastReadAt; // ISO8601
  final String createdAt;
  final String updatedAt;
  final List<Tag> tags;

  /// 计算属性：章节数（由 Provider/DB 层填充，不从 JSON 读取）
  @JsonKey(includeFromJson: false, includeToJson: false)
  final int chapterCount;

  /// 计算属性：阅读进度百分比（由 Provider 层填充）
  @JsonKey(includeFromJson: false, includeToJson: false)
  final double progressPercent;

  const Book({
    this.id,
    required this.title,
    this.author,
    this.summary,
    this.status = '连载中',
    this.sourceUrl,
    this.sourceFormat,
    this.filePath,
    this.coverImage,
    this.coverImagePath,
    this.rating = 0,
    this.notes,
    this.wordCount = 0,
    this.lastReadAt,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.chapterCount = 0,
    this.progressPercent = 0.0,
  });

  factory Book.fromJson(Map<String, dynamic> json) => _$BookFromJson(json);
  Map<String, dynamic> toJson() => _$BookToJson(this);

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? summary,
    String? status,
    String? sourceUrl,
    String? sourceFormat,
    String? filePath,
    String? coverImage,
    String? coverImagePath,
    int? rating,
    String? notes,
    int? wordCount,
    String? lastReadAt,
    String? createdAt,
    String? updatedAt,
    List<Tag>? tags,
    int? chapterCount,
    double? progressPercent,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      summary: summary ?? this.summary,
      status: status ?? this.status,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceFormat: sourceFormat ?? this.sourceFormat,
      filePath: filePath ?? this.filePath,
      coverImage: coverImage ?? this.coverImage,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      rating: rating ?? this.rating,
      notes: notes ?? this.notes,
      wordCount: wordCount ?? this.wordCount,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      chapterCount: chapterCount ?? this.chapterCount,
      progressPercent: progressPercent ?? this.progressPercent,
    );
  }
}

/// 标签模型
@JsonSerializable()
class Tag {
  final int? id;
  final String name;
  final String color; // #RRGGBB

  const Tag({this.id, required this.name, this.color = '#1976D2'});

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);
  Map<String, dynamic> toJson() => _$TagToJson(this);
}