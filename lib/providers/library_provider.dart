import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import 'database_provider.dart';

/// 书库状态
class LibraryState {
  final List<Book> books;
  final List<Tag> tags;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final String? selectedStatus;
  final int? selectedTagId;
  final String sortBy;
  final String sortOrder;
  final int page;
  final int totalCount;
  final Set<int> selectedBookIds;
  final bool isSelectionMode;

  const LibraryState({
    this.books = const [],
    this.tags = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.selectedStatus,
    this.selectedTagId,
    this.sortBy = 'createdAt',
    this.sortOrder = 'desc',
    this.page = 1,
    this.totalCount = 0,
    this.selectedBookIds = const {},
    this.isSelectionMode = false,
  });

  LibraryState copyWith({
    List<Book>? books,
    List<Tag>? tags,
    bool? isLoading,
    String? error,
    String? searchQuery,
    String? selectedStatus,
    int? selectedTagId,
    String? sortBy,
    String? sortOrder,
    int? page,
    int? totalCount,
    Set<int>? selectedBookIds,
    bool? isSelectionMode,
  }) {
    return LibraryState(
      books: books ?? this.books,
      tags: tags ?? this.tags,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedStatus: selectedStatus ?? this.selectedStatus,
      selectedTagId: selectedTagId ?? this.selectedTagId,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
      page: page ?? this.page,
      totalCount: totalCount ?? this.totalCount,
      selectedBookIds: selectedBookIds ?? this.selectedBookIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    );
  }
}

/// 书库 Provider
class LibraryNotifier extends StateNotifier<LibraryState> {
  final DatabaseService _db;

  LibraryNotifier(this._db) : super(const LibraryState());

  /// 加载书籍列表
  Future<void> loadBooks() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      List<Book> books;
      int totalCount;

      if (state.searchQuery.isNotEmpty) {
        // 搜索模式：书名/作者/简介 + 章节标题（不含章节内容）
        books = await _db.searchBooks(state.searchQuery, searchContent: true);
        totalCount = books.length;
      } else {
        // 浏览模式：分页加载
        books = await _db.listBooks(
          page: state.page,
          sortBy: state.sortBy,
          order: state.sortOrder,
          tagId: state.selectedTagId,
          status: state.selectedStatus,
          searchQuery: null,
        );
        totalCount = await _db.getBookCount(
          tagId: state.selectedTagId,
          status: state.selectedStatus,
        );
      }

      // 搜索模式不过滤标签/状态，若需要可二次过滤
      if (state.searchQuery.isNotEmpty && (state.selectedTagId != null || state.selectedStatus != null)) {
        // 对搜索结果进行标签/状态过滤
        if (state.selectedTagId != null) {
          books = books.where((b) => b.tags.map((t) => t.id).contains(state.selectedTagId)).toList();
        }
        if (state.selectedStatus != null && state.selectedStatus != '全部状态') {
          books = books.where((b) => b.status == state.selectedStatus).toList();
        }
        totalCount = books.length;
      }

      state = state.copyWith(books: books, totalCount: totalCount, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 加载所有标签
  Future<void> loadTags() async {
    try {
      final tags = await _db.getAllTags();
      state = state.copyWith(tags: tags);
    } catch (_) {}
  }

  /// 搜索
  Future<void> search(String query) async {
    state = state.copyWith(searchQuery: query, page: 1);
    await loadBooks();
  }

  /// 按标签筛选
  Future<void> filterByTag(int? tagId) async {
    state = state.copyWith(selectedTagId: tagId, page: 1);
    await loadBooks();
  }

  /// 按状态筛选
  Future<void> filterByStatus(String? status) async {
    state = state.copyWith(selectedStatus: status, page: 1);
    await loadBooks();
  }

  /// 排序
  Future<void> sort(String sortBy, String sortOrder) async {
    state = state.copyWith(sortBy: sortBy, sortOrder: sortOrder);
    await loadBooks();
  }

  /// 翻页
  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadBooks();
  }

  /// 添加书籍
  Future<Book> addBook(Book book) async {
    final created = await _db.createBook(book);
    await loadBooks();
    return created;
  }

  /// 更新书籍
  Future<Book> updateBook(Book book) async {
    final updated = await _db.updateBook(book);
    await loadBooks();
    return updated;
  }

  /// 删除书籍
  Future<void> deleteBook(int id) async {
    await _db.deleteBook(id);
    await loadBooks();
  }

  /// 刷新
  Future<void> refresh() async {
    await loadBooks();
    await loadTags();
  }

  /// 进入/退出选择模式
  void toggleSelectionMode() {
    state = state.copyWith(
      isSelectionMode: !state.isSelectionMode,
      selectedBookIds: state.isSelectionMode ? {} : state.selectedBookIds,
    );
  }

  /// 选择/取消选择书籍
  void toggleBookSelection(int bookId) {
    final newSet = Set<int>.from(state.selectedBookIds);
    if (newSet.contains(bookId)) {
      newSet.remove(bookId);
    } else {
      newSet.add(bookId);
    }
    state = state.copyWith(selectedBookIds: newSet);
  }

  /// 全选
  void selectAll() {
    state = state.copyWith(selectedBookIds: state.books.map((b) => b.id!).toSet());
  }

  /// 清除选择
  void clearSelection() {
    state = state.copyWith(selectedBookIds: {});
  }

  /// 获取选中的书籍列表
  List<Book> getSelectedBooks() {
    return state.books.where((b) => state.selectedBookIds.contains(b.id)).toList();
  }
}

/// 书库 Provider 定义
final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier(ref.watch(databaseServiceProvider));
});