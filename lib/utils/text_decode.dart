import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;
import 'package:dart3_big5/big5.dart' show Big5;

/// 文本解码工具 —— 多编码支持（UTF-8 / GBK / GB18030 / GB2312 / Big5）
///
/// 纯 Dart 解码（charset + dart3_big5），桌面端与 Web 端行为一致，
/// 不再依赖平台通道（charset_converter 无 Web 实现导致 Web 端 GBK 乱码的问题已解决）。
///
/// 供导入器(TXT 文件)与爬虫(网页正文)共用：
/// - 自动模式：UTF-8(严格) → GBK/GB18030 → Big5 → UTF-8(替换无效字节)
/// - 手动模式：[encoding] 指定 'utf-8' / 'gbk' / 'gb18030' / 'gb2312' / 'big5'
class TextDecode {
  TextDecode._();

  /// 支持的手动编码选项（设置页「导入设置-默认编码」用）
  static const List<(String, String)> encodingOptions = [
    ('auto', '自动检测'),
    ('utf-8', 'UTF-8'),
    ('gbk', 'GBK / GB2312'),
    ('gb18030', 'GB18030'),
    ('big5', 'Big5（繁体）'),
  ];

  /// 解码字节为字符串。
  static Future<String> decode(Uint8List bytes, {String encoding = 'auto'}) async {
    switch (encoding.toLowerCase()) {
      case 'utf-8':
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        try {
          return gbk.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'big5':
        try {
          return Big5.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'auto':
      default:
        return _autoDecode(bytes);
    }
  }

  /// 自动探测解码：UTF-8 → GBK(含 GB2312/GB18030 常用区) → Big5 → UTF-8 替换
  ///
  /// 性能关键：只用前 64KB 采样探测编码，全文按选定编码**只解码一次**。
  /// 旧实现对全文逐编码尝试解码，大文件最坏产生 3 份全文副本。
  static Future<String> _autoDecode(Uint8List bytes) async {
    const probeSize = 64 * 1024;
    final sample =
        bytes.length > probeSize ? Uint8List.sublistView(bytes, 0, probeSize) : bytes;

    switch (_probeEncoding(sample)) {
      case 'utf-8':
        // 采样段严格有效；全文解码用宽容模式，避免恰好切在多字节字符边界的极端情况
        return utf8.decode(bytes, allowMalformed: true);
      case 'gbk':
        try {
          return gbk.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'big5':
        try {
          return Big5.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 在采样上探测编码，返回 'utf-8' / 'gbk' / 'big5'，全部失败返回 null。
  static String? _probeEncoding(Uint8List sample) {
    // 1. UTF-8（严格解码 + 有效性检查）
    try {
      final text = utf8.decode(sample, allowMalformed: false);
      if (_looksValidChineseText(text)) return 'utf-8';
    } catch (_) {}

    // 2. GBK / GB18030（Big5 字节常被 GBK 解成假名/生僻字，有效性检查会拒绝）
    try {
      final text = gbk.decode(sample);
      if (_looksValidChineseText(text)) return 'gbk';
    } catch (_) {}

    // 3. Big5
    try {
      final text = Big5.decode(sample);
      if (_looksValidChineseText(text)) return 'big5';
    } catch (_) {}

    return null;
  }

  /// 检查解码结果是否像正常中文文本。
  ///
  /// 三个信号任一超标即判无效（换下一个编码尝试）：
  /// 1. Unicode 替换字符/控制字符（解码器容错产物）
  /// 2. 日文假名（GBK 误解 Big5 字节的典型产物，如「いゅ」；中文小说不含假名）
  /// 3. 私用区字符（GBK 众多字节对的映射目标；正常文本不出现）
  static bool _looksValidChineseText(String text) {
    int suspiciousCount = 0;
    int kanaOrPua = 0;
    int hanCount = 0;
    final checkLen = text.length < 2000 ? text.length : 2000;
    for (int i = 0; i < checkLen; i++) {
      final code = text.codeUnitAt(i);
      if (code == 0xFFFD || (code < 0x20 && code != 10 && code != 13 && code != 9)) {
        suspiciousCount++;
      } else if ((code >= 0x3040 && code <= 0x30FF) || // 平假名/片假名
          (code >= 0xE000 && code <= 0xF8FF)) {
        // 私用区
        kanaOrPua++;
      } else if (code >= 0x4E00 && code <= 0x9FFF) {
        hanCount++;
      }
    }
    if (suspiciousCount > 10) return false;
    // 假名/私用区占比超过 0.5%（且存在汉字）视为误解码
    if (hanCount > 0 && kanaOrPua / hanCount > 0.005) return false;
    if (hanCount == 0 && kanaOrPua > 0) return false;
    return true;
  }
}
