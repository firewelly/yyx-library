/// 平台相关的浏览器交互（条件导入入口）。
///
/// - [WebLauncher.openUrl]：用系统默认浏览器/新标签页打开 URL
/// - [WebLauncher.downloadBytes]：把生成的文件字节保存给用户
///   （Web 端触发浏览器下载；桌面端不适用，导出走文件写入）
///
/// 桌面端实现见 `web_launcher_io.dart`，Web 端见 `web_launcher_web.dart`。
library;

export 'web_launcher_io.dart'
    if (dart.library.html) 'web_launcher_web.dart';
