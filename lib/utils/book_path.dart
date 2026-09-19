/// 书籍文件路径的跨系统相对化处理。
///
/// 场景：多设备（macOS/Windows/Linux）通过 OneDrive/NAS 共享同一个数据库
/// （customDbPath），但各设备的挂载/盘符不同，绝对路径互相失效。
/// 方案：数据库统一存「书库根目录」的相对路径（正斜杠分隔），
/// 每台设备在设置里配置自己的 libraryRootPath，展示/访问时再解析。
///
/// - 在根目录下的路径 → 存相对（如 `novels/斗破苍穹.txt`）
/// - 不在根目录下或未配置根目录 → 原样存（绝对路径或文件名）
class BookPath {
  BookPath._();

  static const String _bs = r'\';

  /// 是否为跨平台意义上的绝对路径（盘符 `X:` 或以 `/`、`\` 开头）
  static bool isAbsolute(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('/') || path.startsWith(_bs)) return true;
    // Windows 盘符：D:\ 或 D:/（长度>=3）
    if (path.length >= 3 &&
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path)) {
      return true;
    }
    return false;
  }

  /// 统一分隔符为 `/` 并去除末尾分隔符
  static String normalize(String path) {
    var p = path.replaceAll(_bs, '/');
    p = p.replaceAll(RegExp(r'/{2,}'), '/'); // 折叠连续斜杠（修 /// 形态）
    while (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// 把 [path] 转换为相对 [root] 的存储形式。
  ///
  /// - [root] 为空或 [path] 不在 root 下 → 原样返回（可能是绝对路径或文件名）
  /// - 匹配对大小写不敏感（Windows 盘符大小写不固定）
  static String relativize(String path, String root) {
    if (root.isEmpty || path.isEmpty) return path;
    if (!isAbsolute(path)) return path; // 已是相对路径/文件名

    final nPath = normalize(path);
    final nRoot = normalize(root);
    final lowerPath = nPath.toLowerCase();
    final lowerRoot = nRoot.toLowerCase();

    if (lowerPath == lowerRoot) return '.';
    if (lowerPath.startsWith('$lowerRoot/')) {
      return nPath.substring(nRoot.length + 1);
    }
    return path; // 不在根目录下
  }

  /// 把存储的 [stored] 路径解析为当前设备的绝对路径。
  ///
  /// - 绝对路径 → 原样返回（兼容旧数据/不在根目录下的书）
  /// - 相对路径且配置了 [root] → root 拼接
  /// - 相对路径但未配置 root → 原样返回（仅展示用途）
  static String resolve(String stored, String root) {
    if (stored.isEmpty) return stored;
    if (isAbsolute(stored)) return stored;
    if (root.isEmpty) return stored;
    return '${normalize(root)}/$stored';
  }
}
