/// 桌面端（dart:io）浏览器交互实现。
library;
import 'dart:io';

/// 平台相关的浏览器交互（桌面端实现）
class WebLauncher {
  WebLauncher._();

  /// 用系统默认浏览器打开 URL。
  ///
  /// 只放行 http/https：本地路径或其他协议不交给系统打开——否则
  /// `cmd /c start` 会用默认关联程序（如记事本）打开文件。
  static Future<void> openUrl(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  /// 桌面端不走浏览器下载（导出由 ExportService 直接写文件）。
  /// 该方法仅在 Web 端有意义，这里抛出不支持。
  static Future<void> downloadBytes(
    String fileName,
    List<int> bytes, {
    String? mimeType,
  }) async {
    throw UnsupportedError('浏览器下载仅 Web 端支持');
  }
}
