import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;

/// 章节内容编解码 —— gzip 压缩存储
///
/// 设计要点：
/// - 写入时压缩为 gzip blob（中文纯文本压缩比约 3-5 倍），小章节保持明文（压缩开销不划算）；
/// - 读取时自动识别：明文字符串（旧数据/小章节）与 gzip blob（新数据）均能解码，
///   因此**无需数据库迁移**，存量数据在章节被重写时逐步转为压缩存储；
/// - 纯 Dart 实现（package:archive），桌面端与 Web 端行为一致。
class ContentCodec {
  ContentCodec._();

  /// 小于该长度（字符数）的章节不压缩，编解码开销大于收益
  static const int compressThresholdChars = 4096;

  /// gzip 魔数 0x1F 0x8B
  static bool _isGzip(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;

  /// 编码为可写入 SQLite content 列的值：
  /// 小章节返回 String（明文），大章节返回 Uint8List（gzip blob）
  static Object encode(String text) {
    if (text.length < compressThresholdChars) return text;
    final raw = utf8.encode(text);
    final gzipped = arc.GZipEncoder().encode(raw);
    if (gzipped == null) return text;
    return Uint8List.fromList(gzipped);
  }

  /// 解码 SQLite 读出的 content 值（String 明文 / Uint8List gzip 或 UTF-8 字节）
  static String decode(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List || value is List<int>) {
      final bytes = Uint8List.fromList(value as List<int>);
      if (_isGzip(bytes)) {
        final decoded = arc.GZipDecoder().decodeBytes(bytes);
        return utf8.decode(decoded, allowMalformed: true);
      }
      // 未压缩的原始字节（理论上不应出现，兜底按 UTF-8 解）
      return utf8.decode(bytes, allowMalformed: true);
    }
    return value.toString();
  }
}
