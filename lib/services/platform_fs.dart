/// 平台文件系统门面（条件导入入口）。
///
/// 集中封装所有本地文件操作，使业务代码（导入/导出/备份/扫描/缓存）
/// 不直接 import dart:io，从而可在 Web 构建中编译：
/// - 桌面端：真实文件系统实现（见 `platform_fs_io.dart`）
/// - Web 端：无文件系统，全部抛 [UnsupportedError]（见 `platform_fs_web.dart`）
///
/// Web 端的等价能力由其他路径提供：
/// - 导入：`ImportService.importByBytes`（内存字节流，无需文件路径）
/// - 导出：`WebLauncher.downloadBytes`（浏览器下载）
library;

export 'platform_fs_types.dart';
export 'platform_fs_io.dart'
    if (dart.library.html) 'platform_fs_web.dart';
