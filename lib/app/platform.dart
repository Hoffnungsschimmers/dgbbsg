import 'dart:io';

/// 移动平台判断（Android / iOS）。
/// 用于触摸目标、字号限制、布局密度等平台差异。
bool get kIsMobile => Platform.isAndroid || Platform.isIOS;

/// 桌面平台判断（Windows / macOS / Linux）。
bool get kIsDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
