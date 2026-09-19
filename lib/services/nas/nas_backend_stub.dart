import '../database_service.dart';

/// 非 Web 平台的 NAS 只读模式桩：该模式仅浏览器可用。
Future<DatabaseService> openNasDatabase({required String dbUrl}) async {
  throw UnsupportedError('NAS 只读直连模式仅支持 Web 端（dbUrl: $dbUrl）');
}
