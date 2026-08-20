# 删除历史 Tab + 全面 UI/动画优化

## 一、删除历史功能

### 删除文件（4 个）
- `lib/core/history/history_record.dart`
- `lib/core/history/history_store.dart`
- `lib/features/history/history_tab.dart`
- `test/core/history/history_store_test.dart`

### 编辑文件（2 个）
1. **`lib/app/app.dart`**
   - 删除 `import '../features/history/history_tab.dart'`
   - NavigationRail 和 NavigationBar 中删除"历史"目的地（index 4）
   - `_TabStack` 的 `IndexedStack.children` 中删除 `HistoryTab()`
   - 更新注释 "five tabs" → "four tabs"
   - `nextTab()` / `prevTab()` 的 `% 5` → `% 4`
   - 删除 `Ctrl+5` 快捷键映射（shortcuts.dart 中的 digit5）

2. **`lib/features/subscriptions/subscriptions_state.dart`**
   - 删除 `import '../../core/history/history_record.dart'`
   - 删除 `import '../../core/history/history_store.dart'`
   - 删除 `runLatency()` 中 lines 293-317 的历史保存代码块（try/catch HistoryStore.save）

3. **`lib/app/shortcuts.dart`**
   - 删除 `Ctrl+5` → `SwitchTabIntent(4)` 映射
   - 删除 `Ctrl+6` → `SwitchTabIntent(5)` 映射（已超出范围）

---

## 二、全面 UI/动画优化

### 2.1 Tab 切换动画（`lib/app/app.dart`）
- 将 `_TabStack` 从 `IndexedStack` 改为 `AnimatedSwitcher` + 自定义 `SlideTransition`
- tab 切换时新页面从右侧滑入 + 淡入，旧页面向左滑出 + 淡出
- 使用 `Motion.durBase` (250ms) + `Motion.curveStandard`
- 保留各 tab 的 `AutomaticKeepAliveClientMixin` 状态（用 `IndexedStack` 包裹在 `AnimatedSwitcher` 内，或用 `Offstage` 保持存活）

**实现方案**：保持 `IndexedStack` 不变（保持状态），在 `IndexedStack` 外层加 `AnimatedSwitcher` 做切换过渡。实际上更好的做法是：用一个自定义的 `AnimatedIndexedStack` widget，在 `index` 变化时对当前 child 做 `SlideTransition` + `FadeTransition`。

### 2.2 卡片入场动画（`lib/features/widgets/cards.dart`）
- 给 `card()` 函数增加可选参数 `animate: bool = false`
- 当 `animate: true` 时，用 `flutter_animate` 的 `.fadeIn().slideY(begin: 0.05)` 做淡入上滑
- 在各 tab 的卡片调用处按需启用

### 2.3 药丸状态切换过渡（`lib/features/widgets/pills.dart`）
- 给 `pill()` 和 `pillWithIcon()` 增加 `AnimatedSwitcher` 包裹
- 当文本/颜色变化时，旧 pill 淡出缩小，新 pill 淡入放大
- 使用 `Motion.durFast` (150ms)

### 2.4 日志行入场动画（`lib/features/widgets/log_view.dart`）
- 新日志行从右侧滑入 + 淡入（`SlideTransition` from `Offset(0.1, 0)` + `FadeTransition`）
- 使用 `AnimatedList` 替换当前的 `ListView.builder`，在 `_scheduleFlush` 添加新行时调用 `insertItem`
- 自滚动改用 `animateTo` 替代 `jumpTo`（`Motion.durFast`）

### 2.5 Toast 改进（`lib/features/widgets/toast.dart`）
- 入场：增加轻微 `scale` 弹跳效果（`0.95 → 1.0`）
- 退出：缩短时长到 `Motion.durFast` (150ms)
- 支持点击关闭：添加 `GestureDetector` 的 `onTap` 触发退出动画

### 2.6 统计数字曲线优化（`lib/features/widgets/count_up_text.dart`）
- `TweenAnimationBuilder` 增加 `curve: Curves.easeOutCubic`，数字滚动更自然

### 2.7 统计卡片入场错峰（`lib/features/results/results_stats.dart`）
- 三个统计卡片用 `flutter_animate` 的 stagger 做错峰淡入上滑
- 使用 `Motion.staggerDelay(i)` + `Motion.staggerDur`

### 2.8 可折叠区域内容淡入（`lib/features/widgets/section_collapsible.dart`）
- 展开时内容增加 `FadeTransition`（与 `AnimatedSize` 同步）
- 用同一个 `AnimationController` 驱动 `SizeTransition` + `FadeTransition`

### 2.9 结果表格行删除动画（`lib/features/results/results_table.dart`）
- 删除行时先做淡出 + 向右滑出动画，再移除
- 使用 `AnimatedList` 或 `AnimatedSwitcher` 包裹行

### 2.10 Probe Dashboard 改进（`lib/features/widgets/probe_dashboard.dart`）
- 修复进度环 bug：`TweenAnimationBuilder` 的 `begin` 应该用上一次的值而非 0
- 实时指示灯（绿点）增加脉冲动画（`AnimatedOpacity` 循环）
- 分布条增加宽度过渡动画（`AnimatedContainer`）

### 2.11 空状态动画统一
- 所有 tab 的空状态统一使用相同的 stagger 动画模式（icon → title → subtitle）
- RunTab 的空日志提示也加上入场动画

---

## 三、执行顺序

1. 删除历史功能（文件删除 + 引用清理）
2. Tab 切换动画
3. 卡片/药丸/Toast 等基础组件动画
4. 日志行动画
5. 统计卡片/表格行/ProbeDashboard 等数据展示动画
6. 空状态动画统一

## 四、涉及的文件清单

**删除：** 4 个文件
**编辑：** ~12 个文件
- `lib/app/app.dart` — tab 切换动画 + 删除历史
- `lib/app/shortcuts.dart` — 删除 Ctrl+5/6
- `lib/features/subscriptions/subscriptions_state.dart` — 删除历史保存
- `lib/features/widgets/cards.dart` — 入场动画
- `lib/features/widgets/pills.dart` — 状态过渡
- `lib/features/widgets/log_view.dart` — 日志行动画 + 平滑滚动
- `lib/features/widgets/toast.dart` — 弹跳入场 + 点击关闭
- `lib/features/widgets/count_up_text.dart` — 曲线优化
- `lib/features/widgets/section_collapsible.dart` — 内容淡入
- `lib/features/results/results_stats.dart` — 错峰入场
- `lib/features/results/results_table.dart` — 行删除动画
- `lib/features/widgets/probe_dashboard.dart` — 进度环修复 + 脉冲指示灯 + 分布条动画
- `lib/features/results/results_tab.dart` — 空状态动画
- `lib/features/github_sync/github_sync_tab.dart` — 空状态动画
- `lib/features/subscriptions/run_tab.dart` — 空日志动画