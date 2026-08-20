import 'package:flutter/material.dart';

/// 设计语言：Signal Teal（蓝灰底 + 青绿主色 + 蓝辅色）
/// 主色 = 科技青绿；辅色 = 信号蓝；其余皆为中性蓝灰阶。
/// 明暗两套完整语义令牌（背景/表面/悬停/边框/日志/成功/警示/危险/信息）。
class AppTheme {
  // ---- 品牌色 ----
  static const primary = Color(0xFF0D9488); // teal-600（浅色主色）
  static const primaryDark = Color(0xFF2DD4BF); // teal-400（深色主色）
  static const info = Color(0xFF2563EB); // 信号蓝
  static const infoDark = Color(0xFF60A5FA);

  // ---- 浅色 ----
  static const _lightBg = Color(0xFFF5F7FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceHover = Color(0xFFEFF3F8);
  static const _lightText = Color(0xFF101B2C);
  static const _lightTextDim = Color(0xFF5C6B82);
  static const _lightBorder = Color(0xFFDDE4EE);
  static const _lightLogBg = Color(0xFF0B1526);
  static const _lightLogFg = Color(0xFFB7CBE4);

  // ---- 深色 ----
  static const _darkBg = Color(0xFF0A0F1A);
  static const _darkSurface = Color(0xFF111A2B);
  static const _darkSurfaceHover = Color(0xFF1A2538);
  static const _darkText = Color(0xFFE7EDF6);
  static const _darkTextDim = Color(0xFF8CA0BC);
  static const _darkBorder = Color(0xFF26354D);
  static const _darkLogBg = Color(0xFF060B14);
  static const _darkLogFg = Color(0xFFA9BFD9);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: _lightBg,
        surface: _lightSurface,
        surfaceHover: _lightSurfaceHover,
        text: _lightText,
        textDim: _lightTextDim,
        border: _lightBorder,
        logBg: _lightLogBg,
        logFg: _lightLogFg,
        primary: primary,
        primarySoft: const Color(0xFFCCFBF1),
        onPrimary: Colors.white,
        info: info,
        infoSoft: const Color(0xFFDBEAFE),
        success: const Color(0xFF16A34A),
        warning: const Color(0xFFD97706),
        danger: const Color(0xFFDC2626),
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: _darkBg,
        surface: _darkSurface,
        surfaceHover: _darkSurfaceHover,
        text: _darkText,
        textDim: _darkTextDim,
        border: _darkBorder,
        logBg: _darkLogBg,
        logFg: _darkLogFg,
        primary: primaryDark,
        primarySoft: const Color(0xFF134E4A),
        onPrimary: const Color(0xFF03211D),
        info: infoDark,
        infoSoft: const Color(0xFF1E3A5F),
        success: const Color(0xFF4ADE80),
        warning: const Color(0xFFFBBF24),
        danger: const Color(0xFFF87171),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfaceHover,
    required Color text,
    required Color textDim,
    required Color border,
    required Color logBg,
    required Color logFg,
    required Color primary,
    required Color primarySoft,
    required Color onPrimary,
    required Color info,
    required Color infoSoft,
    required Color success,
    required Color warning,
    required Color danger,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: info,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: text,
      error: danger,
    ).copyWith(
      surface: surface,
      onSurface: text,
    );

    final radius = BorderRadius.circular(12);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'MicrosoftYaHei',
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
          backgroundColor: primary,
          foregroundColor: onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: textDim),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      extensions: [
        AppThemeExt(
          bg: bg,
          surface: surface,
          surfaceHover: surfaceHover,
          text: text,
          textDim: textDim,
          border: border,
          logBg: logBg,
          logFg: logFg,
          primary: primary,
          primarySoft: primarySoft,
          onPrimary: onPrimary,
          info: info,
          infoSoft: infoSoft,
          success: success,
          warning: warning,
          danger: danger,
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
  final Color logBg;
  final Color logFg;
  final Color primary;
  final Color primarySoft;
  final Color onPrimary;
  final Color info;
  final Color infoSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final BorderRadius radius;

  const AppThemeExt({
    required this.bg,
    required this.surface,
    required this.surfaceHover,
    required this.text,
    required this.textDim,
    required this.border,
    required this.logBg,
    required this.logFg,
    required this.primary,
    required this.primarySoft,
    required this.onPrimary,
    required this.info,
    required this.infoSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.radius,
  });

  static AppThemeExt of(BuildContext context) =>
      Theme.of(context).extension<AppThemeExt>()!;

  /// 主色渐变（青绿 → 信号蓝），用于 Hero 卡/品牌元素。
  LinearGradient primaryGradient() => LinearGradient(
        colors: [primary, info],
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
    Color? logBg,
    Color? logFg,
    Color? primary,
    Color? primarySoft,
    Color? onPrimary,
    Color? info,
    Color? infoSoft,
    Color? success,
    Color? warning,
    Color? danger,
    BorderRadius? radius,
  }) =>
      AppThemeExt(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHover: surfaceHover ?? this.surfaceHover,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        border: border ?? this.border,
        logBg: logBg ?? this.logBg,
        logFg: logFg ?? this.logFg,
        primary: primary ?? this.primary,
        primarySoft: primarySoft ?? this.primarySoft,
        onPrimary: onPrimary ?? this.onPrimary,
        info: info ?? this.info,
        infoSoft: infoSoft ?? this.infoSoft,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        radius: radius ?? this.radius,
      );

  @override
  AppThemeExt lerp(ThemeExtension<AppThemeExt>? other, double t) {
    if (other is! AppThemeExt) return this;
    return this;
  }
}