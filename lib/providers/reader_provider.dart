import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

/// 阅读器状态
class ReaderState {
  final Book? currentBook;
  final Chapter? currentChapter;
  final List<Chapter> chapters;
  final ReadingProgress? progress;
  final List<Bookmark> bookmarks;
  final List<Note> notes;
  final bool isLoading;
  final String? error;
  final double fontSize;
  final double marginSize;
  final double lineHeight;
  final int currentScrollPosition;

  const ReaderState({
    this.currentBook,
    this.currentChapter,
    this.chapters = const [],
    this.progress,
    this.bookmarks = const [],
    this.notes = const [],
    this.isLoading = false,
    this.error,
    this.fontSize = 18.0,
    this.marginSize = 60.0,
    this.lineHeight = 1.8,
    this.currentScrollPosition = 0,
  });

  /// 当前章节索引
  int get currentIndex {
    if (currentChapter == null) return -1;
    return chapters.indexWhere((c) => c.id == currentChapter!.id);
  }

  /// 是否有上一章
  bool get hasPrevious => currentIndex > 0;

  /// 是否有下一章
  bool get hasNext => currentIndex < chapters.length - 1;

  /// 阅读进度百分比
  double get progressPercent {
    if (chapters.isEmpty || currentChapter == null) return 0;
    return ((currentIndex + 1) / chapters.length * 100).clamp(0, 100);
  }

  ReaderState copyWith({
    Book? currentBook,
    Chapter? currentChapter,
    List<Chapter>? chapters,
    ReadingProgress? progress,
    List<Bookmark>? bookmarks,
    List<Note>? notes,
    bool? isLoading,
    String? error,
    double? fontSize,
    double? marginSize,
    double? lineHeight,
    int? currentScrollPosition,
  }) {
    return ReaderState(
      currentBook: currentBook ?? this.currentBook,
      currentChapter: currentChapter ?? this.currentChapter,
      chapters: chapters ?? this.chapters,
      progress: progress ?? this.progress,
      bookmarks: bookmarks ?? this.bookmarks,
      notes: notes ?? this.notes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      fontSize: fontSize ?? this.fontSize,
      marginSize: marginSize ?? this.marginSize,
      lineHeight: lineHeight ?? this.lineHeight,
      currentScrollPosition: currentScrollPosition ?? this.currentScrollPosition,
    );
  }
}

/// 阅读器 Provider
class ReaderNotifier extends StateNotifier<ReaderState> {
  final DatabaseService _db;
  final SettingsNotifier _settingsNotifier;

  ReaderNotifier(this._db, this._settingsNotifier) : super(const ReaderState());

  /// 打开书籍阅读
  ///
  /// [initialChapterId] 指定时优先跳转到该章节(深链,如书签跳转);
  /// 否则按阅读进度定位;都没有则从第一章开始。
  Future<void> openBook(int bookId, {int? initialChapterId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final book = await _db.getBook(bookId);
      if (book == null) {
        state = state.copyWith(isLoading: false, error: '书籍不存在');
        return;
      }
      // 轻量加载：只加载章节元数据（不含内容），用于导航列表
      final chapters = await _db.getChapterList(bookId);
      final progress = await _db.getProgress(bookId);
      final bookmarks = await _db.getBookmarks(bookId);
      final notes = await _db.getNotesByBook(bookId);

      // 确定起始章节：深链章节 > 阅读进度 > 第一章
      Chapter? startChapter;
      if (initialChapterId != null) {
        final matching =
            chapters.where((c) => c.id == initialChapterId);
        startChapter = matching.isNotEmpty ? matching.first : null;
      }
      if (startChapter == null && progress != null) {
        final matching = chapters.where((c) => c.id == progress.chapterId);
        startChapter = matching.isNotEmpty ? matching.first : null;
      }
      startChapter ??= chapters.isNotEmpty ? chapters.first : null;

      // 按需加载起始章节的完整内容
      if (startChapter != null && startChapter.id != null) {
        final content = await _db.getChapterContent(startChapter.id!);
        startChapter = startChapter.copyWith(content: content ?? '');
      }

      // 从全局设置加载阅读参数（持久化）
      final settings = _settingsNotifier.state.settings;
      state = state.copyWith(
        currentBook: book,
        currentChapter: startChapter,
        chapters: chapters,
        progress: progress,
        bookmarks: bookmarks,
        notes: notes,
        isLoading: false,
        fontSize: settings.fontSize,
        marginSize: settings.marginSize,
        lineHeight: settings.lineHeight,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 跳转到指定章节（按需加载内容）
  Future<void> goToChapter(int chapterId) async {
    final matching = state.chapters.where((c) => c.id == chapterId);
    if (matching.isEmpty) return;
    var chapter = matching.first;

    // 按需加载该章节的完整内容
    if (chapter.id != null) {
      final content = await _db.getChapterContent(chapter.id!);
      chapter = chapter.copyWith(content: content ?? '');
    }

    // 保存进度（包括当前滚动位置的快照值）
    if (state.currentBook != null) {
      await _db.updateProgress(
        state.currentBook!.id!,
        chapterId,
        scrollPosition: state.currentScrollPosition,
      );
    }

    final progress = await _db.getProgress(state.currentBook!.id!);
    state = state.copyWith(currentChapter: chapter, progress: progress, currentScrollPosition: 0);
  }

  /// 上一章
  Future<void> previousChapter() async {
    if (!state.hasPrevious) return;
    final prevChapter = state.chapters[state.currentIndex - 1];
    await goToChapter(prevChapter.id!);
  }

  /// 下一章
  Future<void> nextChapter() async {
    if (!state.hasNext) return;
    final nextChapter = state.chapters[state.currentIndex + 1];
    await goToChapter(nextChapter.id!);
  }

  /// 调整字体大小（同时持久化到全局设置）
  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
    _settingsNotifier.setFontSize(size);
  }
  void setMarginSize(double size) {
    state = state.copyWith(marginSize: size);
    _settingsNotifier.setMarginSize(size);
  }
  void setLineHeight(double height) {
    state = state.copyWith(lineHeight: height);
    _settingsNotifier.setLineHeight(height);
  }

  /// 关闭阅读器（保存最终阅读进度）
  Future<void> close() async {
    await saveProgress();
    state = const ReaderState();
  }

  /// 更新滚动位置（由 reader_screen 的 ScrollController 调用）
  void updateScrollPosition(int position) {
    state = state.copyWith(currentScrollPosition: position);
  }

  /// 保存当前阅读进度到数据库
  Future<void> saveProgress() async {
    if (state.currentBook == null || state.currentChapter == null) return;
    await _db.updateProgress(
      state.currentBook!.id!,
      state.currentChapter!.id!,
      scrollPosition: state.currentScrollPosition,
    );
  }
}

final readerProvider = StateNotifierProvider<ReaderNotifier, ReaderState>((ref) {
  return ReaderNotifier(
    ref.watch(databaseServiceProvider),
    ref.watch(settingsProvider.notifier),
  );
});