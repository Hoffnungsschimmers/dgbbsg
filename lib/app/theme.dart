import 'package:flutter/material.dart';

import 'platform.dart';

/// 设计语言：Professional Console（专业控制台）
/// 主色 = 信号青绿，辅色 = 信号蓝；中性蓝灰阶；浅色为主，克制耐看。
/// 保留 `edgeOrange` 常量名仅为兼容旧引用（`static const edgeOrange = accent`），
/// 语义上已从橙色切换为青绿主色。
class AppTheme {
  /// 主色（青绿）。
  static const accent = Color(0xFF0E9F6E);

  /// 辅色（信号蓝）：进度/信息/链接。
  static const info = Color(0xFF3B82F6);

  /// 兼容旧引用：= accent（青绿）。
  static const edgeOrange = accent;

  // ---- 浅色 ----
  static const _lightBg = Color(0xFFF6F7F9);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceHover = Color(0xFFEFF2F5);
  static const _lightText = Color(0xFF1A2233);
  static const _lightTextDim = Color(0xFF69758A);
  static const _lightBorder = Color(0xFFE3E7EC);
  // 语义色（light 取可读的深一档）
  static const _lightSuccess = Color(0xFF16A34A);
  static const _lightDanger = Color(0xFFDC2626);
  static const _lightWarning = Color(0xFFD97706);
  static const _lightAccentSoft = Color(0xFFE3F4EC); // 青绿浅底（选中/悬停）
  static const _lightInfoSoft = Color(0xFFE9F0FE); // 蓝浅底

  // ---- 深色 ----
  static const _darkBg = Color(0xFF0F1520);
  static const _darkSurface = Color(0xFF171E2B);
  static const _darkSurfaceHover = Color(0xFF202938);
  static const _darkText = Color(0xFFE6EDF5);
  static const _darkTextDim = Color(0xFF8FA0B5);
  static const _darkBorder = Color(0xFF28344A);
  // 语义色（dark 取亮一档）
  static const _darkSuccess = Color(0xFF4ADE80);
  static const _darkDanger = Color(0xFFF87171);
  static const _darkWarning = Color(0xFFFBBF24);
  static const _darkAccentSoft = Color(0xFF12382B);
  static const _darkInfoSoft = Color(0xFF1B2F55);

  /// 图表配色（6 色循环）：以主色为主轴，中性蓝灰 + 冷色点缀。
  static const List<Color> chartPalette = [
    Color(0xFF0E9F6E), // 青绿主色
    Color(0xFF3B82F6), // 信号蓝
    Color(0xFF6B7280), // 中性灰
    Color(0xFF16A34A), // 成功绿
    Color(0xFFD97706), // 琥珀
    Color(0xFF7C3AED), // 紫
  ];

  /// 深色模式图表配色：亮度更高，确保暗色背景可读。
  static const List<Color> chartPaletteDark = [
    Color(0xFF2DD4A0), // 青绿（更亮）
    Color(0xFF60A5FA), // 蓝（更亮）
    Color(0xFF9CA3AF), // 中性灰（更亮）
    Color(0xFF4ADE80), // 成功绿（更亮）
    Color(0xFFFBBF24), // 琥珀（更亮）
    Color(0xFFA78BFA), // 紫（更亮）
  ];

  static ThemeData light() => _build(
        bg: _lightBg,
        surface: _lightSurface,
        surfaceHover: _lightSurfaceHover,
        text: _lightText,
        textDim: _lightTextDim,
        border: _lightBorder,
        success: _lightSuccess,
        danger: _lightDanger,
        warning: _lightWarning,
        accentSoft: _lightAccentSoft,
        infoSoft: _lightInfoSoft,
        brightness: Brightness.light,
      );

  static ThemeData dark() => _build(
        bg: _darkBg,
        surface: _darkSurface,
        surfaceHover: _darkSurfaceHover,
        text: _darkText,
        textDim: _darkTextDim,
        border: _darkBorder,
        success: _darkSuccess,
        danger: _darkDanger,
        warning: _darkWarning,
        accentSoft: _darkAccentSoft,
        infoSoft: _darkInfoSoft,
        brightness: Brightness.dark,
        chartColors: chartPaletteDark,
      );

  static ThemeData _build({
    required Color bg,
    required Color surface,
    required Color surfaceHover,
    required Color text,
    required Color textDim,
    required Color border,
    required Color success,
    required Color danger,
    required Color warning,
    required Color accentSoft,
    required Color infoSoft,
    required Brightness brightness,
    List<Color>? chartColors,
  }) {
    final effectiveChartPalette = chartColors ?? chartPalette;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
      primary: accent,
      onPrimary: Colors.white,
      secondary: info,
      onSecondary: Colors.white,
      onSurface: text,
    ).copyWith(
      surface: surface,
      onSurface: text,
      surfaceContainer: surface,
    );

    // M3 标准圆角：12px（对应 shape.medium）
    final radius = BorderRadius.circular(12);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'AppSans',
      // M3 Typography Scale：统一文字样式，消除散落的 inline TextStyle
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontSize: 15, color: text),
        bodyMedium: TextStyle(fontSize: 14, color: text),
        bodySmall: TextStyle(fontSize: 13, color: textDim),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: text),
        titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: text),
        titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: text),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
        labelMedium: TextStyle(fontSize: 13, color: textDim),
        labelSmall: TextStyle(fontSize: 12, color: textDim),
      ),
      // 全局输入框样式
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: accent, width: 1.5)),
        hintStyle: TextStyle(color: textDim, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: kIsMobile ? 14 : 12),
          minimumSize: Size(64, kIsMobile ? 48 : 36),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: kIsMobile ? 14 : 12),
          minimumSize: Size(64, kIsMobile ? 48 : 36),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textDim,
          minimumSize: Size(0, kIsMobile ? 48 : 36),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      chipTheme: ChipThemeData(
        backgroundColor: bg,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(fontSize: 12, color: text),
      ),
      tooltipTheme: TooltipThemeData(
        triggerMode: kIsMobile ? TooltipTriggerMode.tap : TooltipTriggerMode.manual,
        showDuration: const Duration(seconds: 3),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        inactiveTrackColor: border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent.withValues(alpha: 0.5);
          return null;
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorColor: accentSoft,
        backgroundColor: bg,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
        unselectedIconTheme: IconThemeData(color: textDim),
        unselectedLabelTextStyle: TextStyle(fontSize: 13, color: textDim),
      ),
      extensions: [
        AppThemeExt(
          bg: bg,
          surface: surface,
          surfaceHover: surfaceHover,
          text: text,
          textDim: textDim,
          border: border,
          success: success,
          danger: danger,
          warning: warning,
          accent: accent,
          accentSoft: accentSoft,
          info: info,
          infoSoft: infoSoft,
          chartPalette: effectiveChartPalette,
          radius: radius,
        ),
      ],
    );
  }
}

/// 主题语义色扩展，供自定义组件直接取色。
class AppThemeExt extends ThemeExtension<AppThemeExt> {
  final Color bg;
  final Color surface;
  final Color surfaceHover;
  final Color text;
  final Color textDim;
  final Color border;
  // 语义色：状态药丸 / 着色日志用。
  final Color success;
  final Color danger;
  final Color warning;
  // 主色/辅色及浅底（选中、悬停、徽标背景）。
  final Color accent;
  final Color accentSoft;
  final Color info;
  final Color infoSoft;
  // 图表配色循环（fl_chart / 自绘 bar 用）。
  final List<Color> chartPalette;
  final BorderRadius radius;

  const AppThemeExt({
    required this.bg,
    required this.surface,
    required this.surfaceHover,
    required this.text,
    required this.textDim,
    required this.border,
    required this.success,
    required this.danger,
    required this.warning,
    required this.accent,
    required this.accentSoft,
    required this.info,
    required this.infoSoft,
    required this.chartPalette,
    required this.radius,
  });

  static AppThemeExt of(BuildContext context) =>
      Theme.of(context).extension<AppThemeExt>()!;

  /// 图表配色按索引取（循环，避免越界）。
  Color chartColor(int i) => chartPalette[i % chartPalette.length];

  /// 主色渐变（青绿 → 蓝），用于品牌元素/横幅。
  LinearGradient accentGradient() => LinearGradient(
        colors: [accent, info],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  @override
  AppThemeExt copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHover,
    Color? text,
    Color? textDim,
    Color? border,
    Color? success,
    Color? danger,
    Color? warning,
    Color? accent,
    Color? accentSoft,
    Color? info,
    Color? infoSoft,
    List<Color>? chartPalette,
    BorderRadius? radius,
  }) =>
      AppThemeExt(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHover: surfaceHover ?? this.surfaceHover,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        border: border ?? this.border,
        success: success ?? this.success,
        danger: danger ?? this.danger,
        warning: warning ?? this.warning,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        info: info ?? this.info,
        infoSoft: infoSoft ?? this.infoSoft,
        chartPalette: chartPalette ?? this.chartPalette,
        radius: radius ?? this.radius,
      );

  @override
  AppThemeExt lerp(ThemeExtension<AppThemeExt>? other, double t) {
    if (other is! AppThemeExt) return this;
    final otherChart = other.chartPalette;
    final n = chartPalette.length < otherChart.length
        ? chartPalette.length
        : otherChart.length;
    final lerpedChart = <Color>[];
    for (var i = 0; i < n; i++) {
      lerpedChart.add(Color.lerp(chartPalette[i], otherChart[i], t)!);
    }
    if (chartPalette.length < otherChart.length) {
      lerpedChart.addAll(otherChart.sublist(n));
    }
    return AppThemeExt(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      chartPalette: lerpedChart,
      radius: BorderRadius.lerp(radius, other.radius, t)!,
    );
  }
}