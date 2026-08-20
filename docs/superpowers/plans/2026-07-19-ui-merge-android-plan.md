# 订阅器页面整合 + Android 适配 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把设置页合并进订阅器页，App 改为单页底部 Tab（配置/运行/结果），修复带宽移除后的残留 bug，并为 Android 打包做结构与权限适配。

**Architecture:** `AppShell` 改为单页 + `NavigationBar` 三 Tab；配置/运行/结果拆为独立 Tab 组件；配置控件 helper 统一到 `features/widgets/common.dart`；输出文件解析到文档目录。结果表移除已无数据的带宽/质量分列。

**Tech Stack:** Flutter 3.44.6 / Dart 3.12.2；flutter_riverpod ^2.5.1；dio ^5.7.0；shared_preferences ^2.3.2；path_provider ^2.1.4。构建命令 `flutter build windows --release`（须先删 `build/windows` 强重建）与 `flutter build apk --release`。

## Global Constraints

- 分支：`feat/subscription-latency-ux`，基于 `main` 8723274；每次提交前保持 `flutter analyze` 0 error。
- 输出文件配置项仍存相对名（`addressesapi.txt` 等），运行时拼接文档目录绝对路径。
- 不引入新第三方依赖（只能用已声明的：riverpod/dio/shared_preferences/path_provider）。
- 删除死代码：`lib/features/settings/` 整体、`settings_fields.dart`、`ResultRow.speed/quality`、`appDirProvider` 若未正式接入则删除。
- Android：`AndroidManifest.xml` 必须声明 `INTERNET` + `ACCESS_NETWORK_STATE`，并 `usesCleartextTraffic="true"`。
- 输入框同步一律用差异守护（`_syncIf`/`_syncList`），避免重新赋值破坏光标/全选。

---

### Task 1: 统一配置控件 helper 到 common.dart

**Files:**
- Modify: `lib/features/widgets/common.dart`
- Test: 无（纯 UI helper，靠后续 build 验证）

**Interfaces:**
- Produces: `labeledTextField`、`labeledSwitch`、`labeledSlider`、`labeledDoubleSlider`、`inputDecorationFor(context)` 供后续 Tab 组件复用。

- [ ] **Step 1: 在 common.dart 末尾追加统一控件 helper**

```dart
/// 统一输入框（带标签 + 等宽字体）。
Widget labeledTextField(
  BuildContext context,
  String label,
  TextEditingController ctl,
  ValueChanged<String> onChanged, {
  bool obscure = false,
}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: t.textDim)),
      const SizedBox(height: 4),
      TextField(
        controller: ctl,
        onChanged: onChanged,
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
        decoration: inputDecorationFor(context),
      ),
    ],
  );
}

/// 统一开关行。
Widget labeledSwitch(BuildContext context, String label, bool value, ValueChanged<bool> onChanged) {
  final t = AppThemeExt.of(context);
  return Row(
    children: [
      Expanded(child: Text(label, style: TextStyle(color: t.text))),
      Switch(value: value, activeThumbColor: AppTheme.edgeOrange, onChanged: onChanged),
    ],
  );
}

/// 统一整数滑块（显示取整）。
Widget labeledSlider(BuildContext context, String label, double value, double min, double max,
    ValueChanged<double> onChanged) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          Text(value.round().toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
        ],
      ),
      Slider(value: value, min: min, max: max, activeColor: AppTheme.edgeOrange, onChanged: onChanged),
    ],
  );
}

/// 统一浮点滑块（显示 1 位小数 + divisions）。
Widget labeledDoubleSlider(BuildContext context, String label, double value, double min, double max,
    ValueChanged<double> onChanged) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          Text(value.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: ((max - min) * 10).round(),
        activeColor: AppTheme.edgeOrange,
        onChanged: onChanged,
      ),
    ],
  );
}

/// 统一输入框装饰。
InputDecoration inputDecorationFor(BuildContext context) {
  final t = AppThemeExt.of(context);
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: t.bg,
    border: OutlineInputBorder(borderRadius: t.radius, borderSide: BorderSide(color: t.border)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
}
```

- [ ] **Step 2: 运行 analyze 确认无错**

Run: `flutter analyze 2>&1 | Select-String -Pattern "error" | Select-Object -First 10`
Expected: 无 error 输出（仅历史 info）。

- [ ] **Step 3: 提交**

```bash
git add lib/features/widgets/common.dart
git commit -m "refactor: 统一配置控件 helper 到 common.dart"
```

---

### Task 2: 结果表移除带宽/质量分残留

**Files:**
- Modify: `lib/features/results/result_state.dart`
- Modify: `lib/features/results/results_page.dart`
- Test: `test/features/results/result_state_test.dart`（新建，验证解析仅含节点/延迟）

**Interfaces:**
- Consumes: `ResultRow`（来自 result_state.dart）
- Produces: 修正后的 `ResultRow(node, [latency])` 与 `parseResultLines`，供结果页使用。

- [ ] **Step 1: 写失败测试**

```dart
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析纯节点与延迟，无带宽/质量分', () {
    final rows = parseResultLines('1.2.3.4:443#US 50.00 ms\n9.9.9.9:443#HK');
    expect(rows.length, 2);
    expect(rows[0].node, '1.2.3.4:443#US');
    expect(rows[0].latency, '50.00 ms');
    expect(rows[0].country, 'US');
    expect(rows[1].latency, isNull);
  });

  test('ResultRow 无 speed/quality 字段', () {
    final r = ResultRow('1.2.3.4:443#US', '50.00 ms');
    expect(r.speed, isNull);   // 编译期保证字段已删
    expect(r.quality, isNull);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/results/result_state_test.dart 2>&1 | Select-Object -Last 8`
Expected: FAIL（字段不存在 / 编译错误）。

- [ ] **Step 3: 修改 result_state.dart**

把 `ResultRow` 改为仅含 `node` 与 `latency`：

```dart
class ResultRow {
  final String node; // ip:port#CC
  final String? latency; // "50.00 ms" 或 null
  ResultRow(this.node, [this.latency]);

  String get ipPort => node.split('#').first;
  String get country => nodeCountry(node);
}
```

`parseResultLines` 仅识别延迟：

```dart
List<ResultRow> parseResultLines(String text) {
  final rows = <ResultRow>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    final node = parts.first;
    if (!node.contains(':')) continue;
    String? latency;
    if (parts.length > 1) {
      final tokens = parts.skip(1).toList();
      for (var i = 0; i < tokens.length; i++) {
        final p = tokens[i];
        if (p.contains('ms')) latency ??= (i > 0 ? '${tokens[i - 1]} $p' : p);
      }
    }
    rows.add(ResultRow(node, latency));
  }
  return rows;
}
```

删除 `ResultState`/`ResultNotifier` 中 `bestSpeed()`/`lowestLatency()` 保留（延迟仍需），删除 `loadMap`（仅 speed 用，已无用）。`geoDistribution()` 保留。

- [ ] **Step 4: 修改 results_page.dart 表格与统计**

- 表格列改为 **节点 / 延迟 / 国家**（`_th`/`_td` 三列，删 `带宽`/`质量分`）。
- 统计卡改为 节点数 / 来源数 / 最低延迟；删除 `_bestSpeed`/`_bestQuality` 及调用。
- `ResultRow` 构造改为 `ResultRow(r.node, r.latency)`（原 `r.speed`/`r.quality` 已删）。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/features/results/result_state_test.dart 2>&1 | Select-Object -Last 6`
Expected: All tests passed!

- [ ] **Step 6: 提交**

```bash
git add lib/features/results/result_state.dart lib/features/results/results_page.dart test/features/results/result_state_test.dart
git commit -m "fix: 结果表移除已无数据的带宽/质量分列"
```

---

### Task 3: 输出文件路径改为文档目录（Android 适配核心）

**Files:**
- Modify: `lib/app/providers.dart`（正式接入 `appDirProvider` 或删除）
- Modify: `lib/features/subscriptions/subscriptions_state.dart`
- Modify: `lib/features/results/result_state.dart`
- Test: `test/core/path/resolve_path_test.dart`（新建）

**Interfaces:**
- Produces: `Future<String> resolveOutputPath(String name)` 工具函数（放在 `lib/core/config/app_config.dart` 或 `subscriptions_state.dart`）。

- [ ] **Step 1: 写失败测试**

```dart
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolveOutputPath 拼接文档目录', () {
    final resolved = resolveOutputPath('addressesapi.txt', '/data/user/0/app/doc');
    expect(p.basename(resolved), 'addressesapi.txt');
    expect(resolved, endsWith('addressesapi.txt'));
  });

  test('绝对路径原样返回', () {
    final resolved = resolveOutputPath('/tmp/x.txt', '/doc');
    expect(resolved, '/tmp/x.txt');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/path/resolve_path_test.dart 2>&1 | Select-Object -Last 6`
Expected: FAIL（函数未定义）。

- [ ] **Step 3: 实现 resolveOutputPath**

在 `lib/core/config/app_config.dart` 末尾添加（不依赖 Flutter，纯路径逻辑，便于测试）：

```dart
/// 把相对输出文件名解析为绝对路径：若已是绝对路径则原样返回，
/// 否则拼接 [baseDir]（运行时为 getApplicationDocumentsDirectory()）。
String resolveOutputPath(String name, String baseDir) {
  if (name.isEmpty) return name;
  final isAbs = name.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(name) ||
      name.startsWith(r'\\');
  return isAbs ? name : '$baseDir/$name'.replaceAll('\\', '/');
}
```

- [ ] **Step 4: 接入运行时目录**

在 `subscriptions_state.dart` 中：`runSubscription`/`runLatency` 用 `await getApplicationDocumentsDirectory()` 得到 `dir`，把 `cfg.subOutputFile`/`cfg.subLatencyOutputFile` 经 `resolveOutputPath(..., dir.path)` 后传给 `writeSubOutput`/`LatencyFilter.run`/`_readNodes`/`resultProvider.loadFile`。

在 `result_state.dart` 的 `loadFile`/`loadRaw` 同样经 `resolveOutputPath` 解析。

`providers.dart` 中 `appDirProvider` 若未被引用则删除；若接入则在调用处 `await ref.read(appDirProvider.future)` 取目录。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/core/path/resolve_path_test.dart 2>&1 | Select-Object -Last 6`
Expected: All tests passed!

- [ ] **Step 6: 提交**

```bash
git add lib/core/config/app_config.dart lib/features/subscriptions/subscriptions_state.dart lib/features/results/result_state.dart lib/app/providers.dart test/core/path/resolve_path_test.dart
git commit -m "feat: 输出文件路径解析到文档目录（Android 适配）"
```

---

### Task 4: 新建配置 Tab（合并设置 + 订阅器配置）

**Files:**
- Create: `lib/features/subscriptions/config_tab.dart`
- Modify: `lib/features/subscriptions/subscriptions_page.dart`（删除，逻辑迁到 config_tab/run_tab）
- Delete: `lib/features/settings/settings_page.dart`, `lib/features/settings/settings_fields.dart`
- Test: 无（UI 整合，靠 analyze + build）

**Interfaces:**
- Consumes: `AppConfig`、`configProvider`、`configRepositoryProvider`、Task 1 的 `labeledTextField`/`labeledSwitch`/`labeledSlider`/`labeledDoubleSlider`、`subProvider`（仅配置项，运行在 run_tab）。
- Produces: `ConfigTab` 组件。

- [ ] **Step 1: 创建 config_tab.dart**

把 `SubscriptionsPage` 中配置相关 build 逻辑（输入模式分段、`_buildGenerators`、`_buildUrls`、Host/UUID/国家码、解析域名、启用订阅转换、延迟优选参数卡片、GitHub 推送卡片）迁移为 `ConfigTab extends ConsumerStatefulWidget`。保留：
  - `_genCtl`/`_urlCtl` 列表 + `_syncList` 守护
  - `_hostCtl`/`_uuidCtl`/`_countryCtl`/`_latencyOutCtl` + `_syncIf` 守护
  - `_save(cfg)` 经 `configRepositoryProvider` 保存
  - 用 Task 1 helper 替换原有 `_textField`/`_switchRow`/`_slider`/`_doubleSlider`/`_text`/`_dec`
  - 延迟优选卡片含 `subLatencyMinSuccessRate`（labeledDoubleSlider）与 `subInsecure`（labeledSwitch）
  - GitHub 卡片含 `githubToken`（labeledTextField obscure:true）、`githubRepo`、`githubBranch`

- [ ] **Step 2: 删除 settings 目录与旧 subscriptions_page.dart**

```bash
git rm lib/features/settings/settings_page.dart lib/features/settings/settings_fields.dart lib/features/subscriptions/subscriptions_page.dart
```

- [ ] **Step 3: analyze 确认无未定义引用**

Run: `flutter analyze 2>&1 | Select-String -Pattern "error" | Select-Object -First 10`
Expected: 无 error。

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "refactor: 合并设置到配置Tab，删除 settings 页与重复 helper"
```

---

### Task 5: 新建运行 Tab 与结果 Tab

**Files:**
- Create: `lib/features/subscriptions/run_tab.dart`
- Modify: `lib/features/results/results_page.dart` → rename to `results_tab.dart`，类 `ResultsPage`→`ResultsTab`，去掉 Scaffold/AppBar 外壳
- Test: 无

**Interfaces:**
- Consumes: `subProvider`、`subLoggerProvider`、`common.dart` 的 `LogView`、Task 2/4 的产物。
- Produces: `RunTab`、`ResultsTab`。

- [ ] **Step 1: 创建 run_tab.dart**

```dart
class RunTab extends ConsumerWidget {
  const RunTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(subProvider);
    final subLogger = ref.watch(subLoggerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppButton('订阅IP', icon: Icons.cloud_download,
                  onPressed: run.running ? null : () => ref.read(subProvider.notifier).runSubscription()),
              AppButton('延迟优选', icon: Icons.speed, primary: false,
                  onPressed: run.running ? null : () => ref.read(subProvider.notifier).runLatency()),
            ],
          ),
        ),
        Expanded(child: LogView(logger: subLogger)),
      ],
    );
  }
}
```

- [ ] **Step 2: 重命名结果页为 Tab**

`git mv lib/features/results/results_page.dart lib/features/results/results_tab.dart`，类改名 `ResultsPage`→`ResultsTab`，删除外部 `Scaffold`/`AppBar`（若原文件无 AppBar 则仅改类名与 build 返回 `Column`/`SingleChildScrollView` 直接作为 Tab 内容）。更新所有 `ResultsPage` 引用为 `ResultsTab`。

- [ ] **Step 3: analyze 确认无错**

Run: `flutter analyze 2>&1 | Select-String -Pattern "error" | Select-Object -First 10`
Expected: 无 error。

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "refactor: 拆分运行Tab与结果Tab，去掉独立页壳"
```

---

### Task 6: AppShell 改为单页底部 Tab

**Files:**
- Modify: `lib/app/app.dart`
- Test: 无

**Interfaces:**
- Consumes: `ConfigTab`(Task4)、`RunTab`(Task5)、`ResultsTab`(Task5)、`pageProvider` 改为 `tabProvider`（int 索引）。

- [ ] **Step 1: 重写 app.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/results/results_tab.dart';
import '../features/subscriptions/config_tab.dart';
import '../features/subscriptions/run_tab.dart';
import 'theme.dart';

final tabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final isWide = MediaQuery.of(context).size.width >= 720;
    final pages = const [ConfigTab(), RunTab(), ResultsTab()];

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: tab,
              onDestinationSelected: (i) => ref.read(tabProvider.notifier).state = i,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.tune), label: Text('配置')),
                NavigationRailDestination(icon: Icon(Icons.play_arrow), label: Text('运行')),
                NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('结果')),
              ],
            ),
            Expanded(child: pages[tab]),
          ],
        ),
      );
    }
    return Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => ref.read(tabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune), label: '配置'),
          NavigationDestination(icon: Icon(Icons.play_arrow), label: '运行'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '结果'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 删除旧 PageKey/SettingsPage 引用与 themeModeProvider 若需保留**

`themeModeProvider` 保留（主题切换仍在 sidebar/rail 外？本设计未含主题切换 UI，若原 sidebar 有则迁移到各 Tab 顶部或暂留待定）。本任务**仅**移除 `PageKey`/`SettingsPage`；`themeModeProvider` 保留定义，引用处若仅 sidebar 使用则删除其 UI（不影响编译，因 provider 定义独立）。

- [ ] **Step 3: analyze 确认无错**

Run: `flutter analyze 2>&1 | Select-String -Pattern "error" | Select-Object -First 10`
Expected: 无 error。

- [ ] **Step 4: 提交**

```bash
git add lib/app/app.dart
git commit -m "refactor: AppShell 改为单页底部Tab(配置/运行/结果)"
```

---

### Task 7: Android Manifest 权限与明文流量

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: 无

**Interfaces:**
- 无代码接口，纯配置。

- [ ] **Step 1: 编辑 AndroidManifest.xml**

在 `<manifest ...>` 内、`<application>` 之前加：

```xml
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

在 `<application android:label="cfnb_app" ...>` 加 `android:usesCleartextTraffic="true"`（保留原有 label/theme/name 属性）。

- [ ] **Step 2: 检查 android 目录存在且未损坏**

Run: `Test-Path android/app/src/main/AndroidManifest.xml`
Expected: True

- [ ] **Step 3: 提交**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "feat: Android 清单声明 INTERNET 与明文流量"
```

---

### Task 8: 全量验证（analyze + test + 双端构建）

**Files:**
- 无新建，验证阶段。

- [ ] **Step 1: flutter analyze**

Run: `flutter analyze 2>&1 | Select-Object -Last 6`
Expected: 0 error（仅历史 info）。

- [ ] **Step 2: flutter test 全量**

Run: `flutter test 2>&1 | Select-Object -Last 8`
Expected: All tests passed!

- [ ] **Step 3: Windows 强重建**

Run: `Remove-Item -Recurse -Force build/windows -ErrorAction SilentlyContinue; flutter build windows --release 2>&1 | Select-Object -Last 6`
Expected: Built build\windows\x64\runner\Release\cfnb_app.exe

- [ ] **Step 4: Android APK 构建**

Run: `flutter build apk --release 2>&1 | Select-Object -Last 8`
Expected: built build/app/outputs/flutter-apk/app-release.apk

- [ ] **Step 5: 提交（若有残留修复）**

若前几步发现需补丁，修复后提交；否则仅记录验证通过，不新建 commit。
