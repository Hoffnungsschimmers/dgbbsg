import 'package:flutter/material.dart';

import 'platform.dart';

/// 设计语言：Edge Telemetry
/// 单一强调色 = Cloudflare 橙 (#ff7a1a)，其余皆为中性灰阶，杜绝"背景与字体同色"。
class AppTheme {
  static const edgeOrange = Color(0xFFFF7A1A);

  static const _lightBg = Color(0xFFFBFAF8);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceHover = Color(0xFFF3F1EC);
  static const _lightText = Color(0xFF1C1917);
  static const _lightTextDim = Color(0xFF78716C);
  static const _lightBorder = Color(0xFFE7E3DC);
  static const _lightLogFg = Color(0xFF1C1917);
  // 语义色（与强调色和谐）。light 下取略深的可读版本。
  static const _lightSuccess = Color(0xFF16A34A);
  static const _lightDanger = Color(0xFFDC2626);
  static const _lightWarning = Color(0xFFD97706);

  static const _darkBg = Color(0xFF0C0A09);
  static const _darkSurface = Color(0xFF1A1714);
  static const _darkSurfaceHover = Color(0xFF262119);
  static const _darkText = Color(0xFFF5F0EA);
  static const _darkTextDim = Color(0xFFA39E96);
  static const _darkBorder = Color(0xFF332D26);
  static const _darkLogFg = Color(0xFFCBD5E1);
  // 语义色 dark 下取略亮的可读版本。
  static const _darkSuccess = Color(0xFF4ADE80);
  static const _darkDanger = Color(0xFFF87171);
  static const _darkWarning = Color(0xFFFBBF24);

  /// 图表配色（6 色循环），以强调橙为主轴，其余抽取自中性/暖色系，保持设计语言。
  static const List<Color> chartPalette = [
    Color(0xFFFF7A1A), // 强调橙
    Color(0xFF6B7280), // 中性灰
    Color(0xFF0EA5E9), // 冷色点缀
    Color(0xFF16A34A), // 成功绿
    Color(0xFFD97706), // 琥珀
    Color(0xFF7C3AED), // 紫
  ];

  /// 深色模式图表配色：亮度更高，确保在暗色背景上的可读性。
  static const List<Color> chartPaletteDark = [
    Color(0xFFFF8C3A), // 强调橙（更亮）
    Color(0xFF9CA3AF), // 中性灰（更亮）
    Color(0xFF38BDF8), // 冷色点缀（更亮）
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
        logFg: _lightLogFg,
        success: _lightSuccess,
        danger: _lightDanger,
        warning: _lightWarning,
        brightness: Brightness.light,
      );

  static ThemeData dark() => _build(
        bg: _darkBg,
        surface: _darkSurface,
        surfaceHover: _darkSurfaceHover,
        text: _darkText,
        textDim: _darkTextDim,
        border: _darkBorder,
        logFg: _darkLogFg,
        success: _darkSuccess,
        danger: _darkDanger,
        warning: _darkWarning,
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
    required Color logFg,
    required Color success,
    required Color danger,
    required Color warning,
    required Brightness brightness,
    List<Color>? chartColors,
  }) {
    final effectiveChartPalette = chartColors ?? chartPalette;
    final scheme = ColorScheme.fromSeed(
      seedColor: edgeOrange,
      brightness: brightness,
      surface: surface,
      primary: edgeOrange,
      onPrimary: Colors.white,
      onSurface: text,
    ).copyWith(
      surface: surface,
      onSurface: text,
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
      // 全局输入框样式：统一样式，消除 inputDecorationFor 的重复构造
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: edgeOrange, width: 1.5)),
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
          backgroundColor: edgeOrange,
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
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: edgeOrange,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bg,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(fontSize: 12, color: text),
      ),
      // Tooltip 触发时机：移动端用 tap（hover 不存在），桌面用 manual
      tooltipTheme: TooltipThemeData(
        triggerMode: kIsMobile ? TooltipTriggerMode.tap : TooltipTriggerMode.manual,
        showDuration: const Duration(seconds: 3),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: edgeOrange,
        thumbColor: edgeOrange,
        overlayColor: edgeOrange.withValues(alpha: 0.12),
        inactiveTrackColor: border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return edgeOrange;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return edgeOrange.withValues(alpha: 0.5);
          return null;
        }),
      ),
      extensions: [
        AppThemeExt(
          bg: bg,
          surface: surface,
          surfaceHover: surfaceHover,
          text: text,
          textDim: textDim,
          border: border,
          logFg: logFg,
          success: success,
          danger: danger,
          warning: warning,
          chartPalette: effectiveChartPalette,
          radius: radius,
        ),
      ],
    );
  }
}

/// 主题语义色扩展，供自定义组件直接取色（对应旧版 C 字典）。
class AppThemeExt extends ThemeExtension<AppThemeExt> {
  final Color bg;
  final Color surface;
  final Color surfaceHover;
  final Color text;
  final Color textDim;
  final Color border;
  final Color logFg;
  // 语义色：状态药丸 / 延迟分级 / 着色日志用。
  final Color success;
  final Color danger;
  final Color warning;
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
    required this.logFg,
    required this.success,
    required this.danger,
    required this.warning,
    required this.chartPalette,
    required this.radius,
  });

  static AppThemeExt of(BuildContext context) =>
      Theme.of(context).extension<AppThemeExt>()!;

  /// 延迟分级颜色：<80ms 成功 / <150ms 警告 / <300ms 强调橙 / 否则危险。
  /// 复用于表格行内条形图与状态药丸。
  Color latencyTierColor(double? latencyMs) {
    if (latencyMs == null) return textDim;
    if (latencyMs < 80) return success;
    if (latencyMs < 150) return warning;
    if (latencyMs < 300) return AppTheme.edgeOrange;
    return danger;
  }

  /// 图表配色按索引取（循环，避免越界）。
  Color chartColor(int i) => chartPalette[i % chartPalette.length];

  @override
  AppThemeExt copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHover,
    Color? text,
    Color? textDim,
    Color? border,
    Color? logFg,
    Color? success,
    Color? danger,
    Color? warning,
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
        logFg: logFg ?? this.logFg,
        success: success ?? this.success,
        danger: danger ?? this.danger,
        warning: warning ?? this.warning,
        chartPalette: chartPalette ?? this.chartPalette,
        radius: radius ?? this.radius,
      );

  @override
  AppThemeExt lerp(ThemeExtension<AppThemeExt>? other, double t) {
    if (other is! AppThemeExt) return this;
    // 调色板逐项插值；长度不一致则短的一方补齐对方剩余项。
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
      logFg: Color.lerp(logFg, other.logFg, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      chartPalette: lerpedChart,
      radius: BorderRadius.lerp(radius, other.radius, t)!,
    );
  }
}
