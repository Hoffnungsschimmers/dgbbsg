import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

class SystemTrayManager {
  final SystemTray _tray = SystemTray();

  /// 将打包进资源的 logo 解包到临时目录（system_tray 需要真实文件路径，
  /// 打包后的发行版中不存在 assets/ 文件系统路径）。
  Future<String> _extractIconToTemp() async {
    final data = await rootBundle.load('assets/icon/logo.png');
    final dir = await Directory.systemTemp.createTemp('cfnb_tray');
    final f = File('${dir.path}/logo.png');
    await f.writeAsBytes(data.buffer.asUint8List());
    return f.path;
  }

  Future<void> init({
    VoidCallback? onShow,
    VoidCallback? onRunSub,
    VoidCallback? onRunLatency,
    VoidCallback? onQuit,
  }) async {
    final iconPath = await _extractIconToTemp();

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
