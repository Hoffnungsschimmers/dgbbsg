import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 应用全局快捷键 Intent 定义。
/// Intent 是"做什么"的语义描述，Shortcut 绑定"按什么键触发"。
class SwitchTabIntent extends Intent {
  final int index;
  const SwitchTabIntent(this.index);
}

class NextTabIntent extends Intent {
  const NextTabIntent();
}

class PrevTabIntent extends Intent {
  const PrevTabIntent();
}

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class ToggleEditModeIntent extends Intent {
  const ToggleEditModeIntent();
}

class RunSubscriptionIntent extends Intent {
  const RunSubscriptionIntent();
}

class CancelRunIntent extends Intent {
  const CancelRunIntent();
}

/// 全局快捷键绑定表（Ctrl/F 系列优先，桌面专用）。
Map<ShortcutActivator, Intent> buildAppShortcuts() {
  return <ShortcutActivator, Intent>{
    // Tab 切换
    const SingleActivator(LogicalKeyboardKey.digit1, control: true): const SwitchTabIntent(0),
    const SingleActivator(LogicalKeyboardKey.digit2, control: true): const SwitchTabIntent(1),
    const SingleActivator(LogicalKeyboardKey.digit3, control: true): const SwitchTabIntent(2),
    const SingleActivator(LogicalKeyboardKey.digit4, control: true): const SwitchTabIntent(3),
    const SingleActivator(LogicalKeyboardKey.tab, control: true): const NextTabIntent(),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): const PrevTabIntent(),

    // 刷新
    const SingleActivator(LogicalKeyboardKey.keyR, control: true): const RefreshIntent(),
    const SingleActivator(LogicalKeyboardKey.f5): const RefreshIntent(),

    // 编辑模式
    const SingleActivator(LogicalKeyboardKey.keyE, control: true): const ToggleEditModeIntent(),

    // 运行操作
    const SingleActivator(LogicalKeyboardKey.keyB, control: true): const RunSubscriptionIntent(),
    const SingleActivator(LogicalKeyboardKey.period, control: true): const CancelRunIntent(),
  };
}
