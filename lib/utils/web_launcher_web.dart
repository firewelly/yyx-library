/// Web 端浏览器交互实现（dart:html 仅在本文件引用，不影响其他平台编译）。
library;
import 'dart:html' as html;
import 'dart:typed_data';

/// 平台相关的浏览器交互（Web 端实现）

// dart:html 在非 wasm 构建下仍是标准做法；迁移 package:web 留待 wasm 支持时
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
class WebLauncher {
  WebLauncher._();

  /// 在新标签页打开 URL
  static Future<void> openUrl(String url) async {
    html.window.open(url, '_blank');
  }

  /// 触发浏览器下载（用 Blob + 隐藏 <a download>）
  static Future<void> downloadBytes(
    String fileName,
    List<int> bytes, {
    String? mimeType,
  }) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = html.Blob([data], mimeType ?? 'application/octet-stream');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}
