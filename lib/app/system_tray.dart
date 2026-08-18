import 'dart:io';

import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class SystemTrayManager {
  final SystemTray _tray = SystemTray();

  Future<void> init({
    VoidCallback? onShow,
    VoidCallback? onRunSub,
    VoidCallback? onRunLatency,
    VoidCallback? onQuit,
  }) async {
    // Determine the correct icon path for the platform.
    // On Windows the .ico is preferred; fall back to the PNG.
    String iconPath;
    if (Platform.isWindows) {
      iconPath = 'assets/icon/logo.ico';
      // If the .ico file does not exist, use the PNG instead.
      if (!File(iconPath).existsSync()) {
        iconPath = 'assets/icon/logo.png';
      }
    } else {
      iconPath = 'assets/icon/logo.png';
    }

    // Initialize the tray icon.
    await _tray.initSystemTray(
      title: 'CFNB - CF优选工具',
      iconPath: iconPath,
      toolTip: 'CFNB - CF优选工具',
    );

    // Build the context menu.
    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: '显示窗口',
        onClicked: (_) => onShow?.call(),
      ),
      MenuItemLabel(
        label: '运行订阅IP',
        onClicked: (_) => onRunSub?.call(),
      ),
      MenuItemLabel(
        label: '运行延迟优选',
        onClicked: (_) => onRunLatency?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '退出',
        onClicked: (_) => onQuit?.call(),
      ),
    ]);

    await _tray.setContextMenu(menu);

    // Double-click the tray icon to show the window.
    _tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        onShow?.call();
      } else if (eventName == kSystemTrayEventDoubleClick) {
        onShow?.call();
      }
    });
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideToTray() async {
    await windowManager.hide();
  }

  void dispose() {
    _tray.destroy();
  }
}
