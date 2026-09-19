/// 应用常量
class AppConstants {
  AppConstants._();

  // 功能开关：网络书源抓取入口。
  // 上架/分发版本通过 --dart-define=ENABLE_CRAWLER=false 隐藏入口；
  // 默认开启，保持本地开发与个人使用的工作流不变。
  static const bool enableCrawler = bool.fromEnvironment(
    'ENABLE_CRAWLER',
    defaultValue: true,
  );

  // 数据库
  static const String dbName = 'novelmgt.db';
  static const int dbVersion = 1;

  // 阅读设置范围
  static const double minFontSize = 12.0;
  static const double maxFontSize = 30.0;
  static const double fontSizeStep = 1.0;
  static const double defaultFontSize = 18.0;

  static const double minMargin = 20.0;
  static const double maxMargin = 200.0;
  static const double marginStep = 10.0;
  static const double defaultMargin = 60.0;

  static const double minLineHeight = 1.0;
  static const double maxLineHeight = 3.0;
  static const double lineHeightStep = 0.1;
  static const double defaultLineHeight = 1.8;

  // 响应式断点
  static const double mobileBreakpoint = 600.0;
  static const double tabletBreakpoint = 1200.0;

  // 分页
  static const int defaultPageSize = 20;
  static const int defaultChapterPageSize = 50;

  // 书籍状态
  static const String statusOngoing = '连载中';
  static const String statusCompleted = '已完结';
  static const List<String> bookStatuses = [statusOngoing, statusCompleted];

  // 评分
  static const int minRating = 0;
  static const int maxRating = 5;

  // 导出格式
  static const String exportFormatTxt = 'txt';
  static const String exportFormatEpub = 'epub';

  // Hive box 名
  static const String settingsBox = 'app_settings';
}