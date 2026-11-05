import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/s.dart';
import '../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'router/app_router.dart';

/// 应用根组件
class NovelMgtApp extends ConsumerWidget {
  const NovelMgtApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final palette = AppPalette.byId(settingsState.settings.themeSeed);

    // 语言设置变化时整体重建，使 t() 输出全部刷新
    final lang = settingsState.settings.language;
    S.configure(lang);

    return MaterialApp.router(
      key: ValueKey('locale-$lang'),
      locale: S.resolvedLocale,
      title: t('YYX书库'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(palette),
      darkTheme: AppTheme.darkTheme(palette),
      themeMode: settingsState.themeMode,
      routerConfig: appRouter,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
    );
  }
}