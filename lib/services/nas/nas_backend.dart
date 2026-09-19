// NAS 只读库接入点（条件导入）。
//
// Web 端（dart.library.html）：浏览器经 HTTP Range 直读 NAS 上的单文件库；
// 其他平台：不支持（openNasDatabase 抛 UnsupportedError）。
export 'nas_backend_stub.dart'
    if (dart.library.html) 'nas_backend_web.dart';
