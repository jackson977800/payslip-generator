import 'package:flutter/material.dart';

/// 全局设计系统。
///
/// 之前每个页面各自写 Card / 间距 / 圆角，导致同一件事在不同页长得不一样
/// （设置页圆角 12 带描边、其他页用默认 elevation）。
/// 这里把颜色、间距、圆角、卡片、输入框、按钮统一收口，
/// 各页面只引用常量与共用组件，不再各写各的。
class AppTheme {
  AppTheme._();

  /// 主色：偏深的墨绿，和「钱 / 账单」的语义搭，也不像默认蓝那么刺眼
  static const seed = Color(0xFF2F6B4F);

  // ---------------------------------------------------------------- 语义色
  /// 成功（已发送 / 已存档）
  static const okLight = Color(0xFF1B7F4B);
  static const okDark = Color(0xFF6BD79B);

  /// 待处理（未发送 / 仅底薪）
  static const warnLight = Color(0xFF9A6400);
  static const warnDark = Color(0xFFF2C14E);

  /// 金额为负时的颜色
  static const negLight = Color(0xFFB3261E);
  static const negDark = Color(0xFFFF8A80);

  static Color ok(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? okDark : okLight;
  static Color warn(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? warnDark : warnLight;
  static Color neg(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? negDark : negLight;

  // ---------------------------------------------------------------- 间距
  static const gapXs = 4.0;
  static const gapSm = 8.0;
  static const gapMd = 12.0;
  static const gapLg = 16.0;
  static const gapXl = 24.0;

  /// 统一圆角
  static const radius = 12.0;
  static const radiusSm = 8.0;

  static const pagePadding = EdgeInsets.fromLTRB(gapMd, gapMd, gapMd, gapXl);

  // ---------------------------------------------------------------- 主题
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    final border = isDark
        ? scheme.outlineVariant.withValues(alpha: 0.5)
        : scheme.outlineVariant;

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,

      // AppBar：和背景同色，靠标题字重分层，不要阴影
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),

      // 卡片：无阴影 + 细描边。阴影在深色模式几乎看不见，
      // 描边两种模式下都稳定，视觉也更干净。
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : scheme.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: gapMd, vertical: gapMd),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
        floatingLabelStyle: TextStyle(color: scheme.primary, fontSize: 13),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm)),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm)),
          side: BorderSide(color: border),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm)),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11.5,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant,
            )),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
        labelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),

      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: gapLg,
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm)),
        titleTextStyle: base.textTheme.bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius + 4)),
        titleTextStyle: base.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm)),
        backgroundColor: isDark ? scheme.surfaceContainerHighest : null,
        contentTextStyle: isDark
            ? TextStyle(color: scheme.onSurface, fontSize: 13.5)
            : null,
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm)),
        side: BorderSide(color: border),
        labelStyle: const TextStyle(fontSize: 11.5),
        padding: const EdgeInsets.symmetric(horizontal: gapSm, vertical: 0),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(gapXs)),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.primary : null),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
