/// 书源规则模型 —— 通用爬虫引擎的配置驱动
///
/// 书源以 JSON 描述一个小说网站的抓取规则:
/// - [search]: 搜索规则(可选,某些站不支持搜索)
/// - [toc]: 目录页规则(必须)
/// - [content]: 正文页规则(必须)
///
/// 选择器语法:`CSS选择器@属性`,缺省属性取文本(text)。
/// URL 模板支持 `{{key}}`(搜索词)、`{{bookUrl}}`(书籍 URL)占位符。
///
/// 参考:legado 阅读书源规则的精简版 + 项目内 novel2_project/config.py 的
/// `选择器@属性` 约定。
class BookSource {
  final String name;
  final String baseUrl;
  final SearchRule? search;
  final TocRule toc;
  final ContentRule content;
  final bool enabled;
  final int sortOrder;

  const BookSource({
    required this.name,
    required this.baseUrl,
    this.search,
    required this.toc,
    required this.content,
    this.enabled = true,
    this.sortOrder = 0,
  });

  factory BookSource.fromJson(Map<String, dynamic> json) {
    return BookSource(
      name: json['name'] as String? ?? '未命名书源',
      baseUrl: json['baseUrl'] as String? ?? '',
      search: json['search'] is Map
          ? SearchRule.fromJson(json['search'] as Map<String, dynamic>)
          : null,
      toc: TocRule.fromJson(json['toc'] as Map<String, dynamic>? ?? {}),
      content: ContentRule.fromJson(json['content'] as Map<String, dynamic>? ?? {}),
      enabled: json['enabled'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        if (search != null) 'search': search!.toJson(),
        'toc': toc.toJson(),
        'content': content.toJson(),
        'enabled': enabled,
        'sortOrder': sortOrder,
      };
}

/// 搜索规则
class SearchRule {
  final String url;
  final String listSelector; // 搜索结果行容器
  final String title; // 书名
  final String urlRule; // 书籍 URL
  final String author; // 作者(可空)

  const SearchRule({
    required this.url,
    required this.listSelector,
    required this.title,
    required this.urlRule,
    this.author = '',
  });

  factory SearchRule.fromJson(Map<String, dynamic> json) => SearchRule(
        url: json['url'] as String? ?? '',
        listSelector: json['listSelector'] as String? ?? '',
        title: json['title'] as String? ?? '',
        urlRule: json['urlRule'] as String? ?? json['url'] as String? ?? 'href',
        author: json['author'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'listSelector': listSelector,
        'title': title,
        'urlRule': urlRule,
        'author': author,
      };
}

/// 目录页规则
class TocRule {
  final String url; // 目录页 URL 模板(用 {{bookUrl}})
  final String listSelector; // 章节链接容器
  final String title; // 章节标题
  final String urlRule; // 章节 URL

  const TocRule({
    required this.url,
    required this.listSelector,
    this.title = 'text',
    this.urlRule = 'href',
  });

  factory TocRule.fromJson(Map<String, dynamic> json) => TocRule(
        url: json['url'] as String? ?? '{{bookUrl}}',
        listSelector: json['listSelector'] as String? ?? '',
        title: json['title'] as String? ?? 'text',
        urlRule: json['urlRule'] as String? ?? json['url'] as String? ?? 'href',
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'listSelector': listSelector,
        'title': title,
        'urlRule': urlRule,
      };
}

/// 正文页规则
class ContentRule {
  final String selector; // 正文内容选择器
  final List<String> cleanPatterns; // 清洗正则(过滤广告行等)

  const ContentRule({
    required this.selector,
    this.cleanPatterns = const [],
  });

  factory ContentRule.fromJson(Map<String, dynamic> json) => ContentRule(
        selector: json['selector'] as String? ?? '',
        cleanPatterns: (json['cleanPatterns'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'selector': selector,
        'cleanPatterns': cleanPatterns,
      };
}

/// 爬取结果中的一本书(搜索结果)
class CrawledBook {
  final String title;
  final String author;
  final String url;
  final String sourceName;

  const CrawledBook({
    required this.title,
    required this.author,
    required this.url,
    required this.sourceName,
  });
}

/// 爬取到的章节(目录项)
class CrawledChapter {
  final String title;
  final String url;
  final int chapterNumber;

  const CrawledChapter({
    required this.title,
    required this.url,
    required this.chapterNumber,
  });
}

/// 内置默认书源(从现有 Python 爬虫经验提取选择器)
const List<BookSource> kDefaultBookSources = [
  // zzxx.org —— 项目主站(archieve/novel2_project + zzxx_crawler.py 经验)
  BookSource(
    name: 'zzxx.org',
    baseUrl: 'https://www.zzxx.org',
    search: SearchRule(
      url: 'https://www.zzxx.org/modules/article/search.php?searchkey={{key}}',
      listSelector: 'table.result-item',
      title: 'a@title',
      urlRule: 'a@href',
      author: 'td.author',
    ),
    toc: TocRule(
      url: '{{bookUrl}}',
      listSelector: 'div#list dl dd a',
      title: 'text',
      urlRule: 'href',
    ),
    content: ContentRule(
      selector: 'div#htmlContent',
      cleanPatterns: [
        r'^https?://[^\s]+$',
        r'^(手机阅读|txt下载|最新章节|无弹窗|请收藏)[^\n]*',
      ],
    ),
  ),
  // yebiquge.com(work_folder/novel_scraper_with_resume_v2_2.py 经验)
  BookSource(
    name: 'yebiquge.com',
    baseUrl: 'https://www.yebiquge.com',
    search: SearchRule(
      url: 'https://www.yebiquge.com/modules/article/search.php?searchkey={{key}}',
      listSelector: 'table.result-item',
      title: 'a@title',
      urlRule: 'a@href',
      author: 'td.author',
    ),
    toc: TocRule(
      url: '{{bookUrl}}',
      listSelector: 'div#list dl dd a',
      title: 'text',
      urlRule: 'href',
    ),
    content: ContentRule(
      selector: 'div#content',
      cleanPatterns: [
        r'^https?://[^\s]+$',
        r'^(请收藏|手机阅读|最新章节|无弹窗)[^\n]*',
      ],
    ),
  ),
  // 22biqu.com(v2_2 经验:div#list + div#content)
  BookSource(
    name: '22biqu.com',
    baseUrl: 'https://www.22biqu.com',
    search: SearchRule(
      url: 'https://www.22biqu.com/search.html?q={{key}}',
      listSelector: 'table.result-item',
      title: 'a@title',
      urlRule: 'a@href',
      author: 'td.author',
    ),
    toc: TocRule(
      url: '{{bookUrl}}',
      listSelector: 'div#list dl dd a',
      title: 'text',
      urlRule: 'href',
    ),
    content: ContentRule(
      selector: 'div#content',
      cleanPatterns: [
        r'^https?://[^\s]+$',
        r'^(请收藏|手机阅读|最新章节|无弹窗)[^\n]*',
      ],
    ),
  ),
];
