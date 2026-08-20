# 首页空白修复 + 结果页 GitHub 推送与地址复制 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复首页首帧透明（空白）bug，并在结果页新增「推送 GitHub」和「地址」按钮。

**Architecture:** ① `_TabStackState.initState` 补 `_ctrl.value = 1.0` 让首帧动画处于完成态；② 结果页复用现有 `GithubPush`，通过新增的 `githubPushProvider` 注入构造（便于测试 mock sender），序列化复用提取出的 `ResultState.toText()`。

**Tech Stack:** Flutter / Riverpod / Dio / flutter_test

## Global Constraints

- 不新增第三方依赖（复用 dio、flutter/services 的 Clipboard、AppToast）。
- UI 文案使用中文。
- 仓库/分支/token 一律来自 `AppConfig` 字段（`githubRepo`/`githubBranch`/`githubToken`）。
- raw 地址格式：`https://raw.githubusercontent.com/{repo}/refs/heads/{branch}/{fileName}`（用户指定格式，`refs/heads/` 必须保留）。
- 目标仓库默认值改为 `Hoffnungsschimmers/mnscn`，文件推送到仓库根目录。
- 完成标准：`flutter analyze` 0 error、全量 `flutter test` 通过。
- 提交 git 需用户另行确认（本计划不含 commit 步骤）。

---

### Task 1: 首页首帧空白修复

**Files:**
- Modify: `lib/app/app.dart:204-211`（`_TabStackState.initState`）
- Test: `test/app/app_test.dart`（新建）

**Interfaces:**
- Consumes: 无
- Produces: 无（纯行为修复）

- [ ] **Step 1: 写失败测试**

创建 `test/app/app_test.dart`：

```dart
import 'package:cfnb_app/app/app.dart';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/features/subscriptions/config_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('首帧首页（配置页）透明度为 1，无需切页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        configRepositoryProvider.overrideWith((ref) => repo),
        configProvider.overrideWith((ref) async => const AppConfig()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AppShell(),
      ),
    ));

    // _TabStack 的 FadeTransition 是 ConfigTab 最近的一个 FadeTransition 祖先
    final fade = tester.widget<FadeTransition>(find
        .ancestor(of: find.byType(ConfigTab), matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, 1.0);
    expect(find.byType(ConfigTab), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/app/app_test.dart`
Expected: FAIL，`fade.opacity.value` 为 0.0（首帧 `_newFade` 停在起始值）

- [ ] **Step 3: 最小实现**

`lib/app/app.dart` `_TabStackState.initState`（L204-211）改为：

```dart
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: Motion.durBase, vsync: this)
      ..addStatusListener(_onStatus);
    _curve = CurvedAnimation(parent: _ctrl, curve: Motion.curveStandard);
    _buildAnimations(0);
    // 首帧直接处于动画完成态：否则当前 tab 透明度为 0，首页空白，
    // 必须切换 tab（didUpdateWidget 里 forward）后才可见。
    _ctrl.value = 1.0;
  }
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/app/app_test.dart`
Expected: PASS

---

### Task 2: 提取 `ResultState.toText()` 序列化

**Files:**
- Modify: `lib/features/results/result_state.dart`（`ResultState` 类加方法；`saveToFile` 复用）
- Test: `test/features/results/results_tab_test.dart`（ResultNotifier group 内加测试）

**Interfaces:**
- Produces: `String ResultState.toText()` —— 每行 `node` + latency（若有），空格分隔，`\n` 结尾；行序即 rows 顺序。

- [ ] **Step 1: 写失败测试**

在 `test/features/results/results_tab_test.dart` 的 `group('ResultNotifier')` 内追加：

```dart
    test('toText 序列化 node 与延迟', () {
      notifier.setRows([
        ResultRow('1.2.3.4:443#US mia', '50.00 ms'),
        ResultRow('5.6.7.8:443#JP'),
      ]);
      expect(notifier.state.toText(),
          '1.2.3.4:443#US mia 50.00 ms\n5.6.7.8:443#JP\n');
    });

    test('toText 空列表输出空字符串', () {
      expect(notifier.state.toText(), '');
    });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/results/results_tab_test.dart`
Expected: FAIL（`toText` 未定义，编译错误）

- [ ] **Step 3: 最小实现**

`lib/features/results/result_state.dart`，在 `ResultState` 类中 `filteredRows` getter 之后加：

```dart
  /// 序列化为文件/推送内容：每行 `node [latency]`，行序即列表顺序。
  String toText() {
    final sb = StringBuffer();
    for (final r in rows) {
      final parts = <String>[r.node];
      if (r.latency != null) parts.add(r.latency!);
      sb.writeln(parts.join(' '));
    }
    return sb.toString();
  }
```

并把 `ResultNotifier.saveToFile`（L286-300）改为复用：

```dart
  /// 将当前节点列表写回文件（覆盖）。
  Future<void> saveToFile() async {
    final path = state.currentFile;
    if (path == null) return;
    final resolved = resolveOutputPath(path, (await getApplicationDocumentsDirectory()).path);
    final text = state.toText();
    await File(resolved).writeAsString(text);
    // 同步更新 rawText
    state = state.copyWith(rawText: text);
  }
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/results/results_tab_test.dart`
Expected: PASS（新旧测试全部通过）

---

### Task 3: 默认 GitHub 仓库改为 mnscn

**Files:**
- Modify: `lib/core/config/app_config.dart:35`
- Modify: `test/core/config/app_config_test.dart:20`

**Interfaces:**
- Produces: `AppConfig.githubRepo` 默认值 `'Hoffnungsschimmers/mnscn'`

- [ ] **Step 1: 改失败测试（先改断言）**

`test/core/config/app_config_test.dart` L20：

```dart
      expect(c.githubRepo, 'Hoffnungsschimmers/mnscn');
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/config/app_config_test.dart`
Expected: FAIL（默认值仍为旧仓库名）

- [ ] **Step 3: 实现**

`lib/core/config/app_config.dart` L35：

```dart
  final String githubRepo; // 形如 "owner/repo"
```

改为默认值：

```dart
  final String githubRepo = 'Hoffnungsschimmers/mnscn'; // 形如 "owner/repo"
```

若该字段是构造参数带默认值（`this.githubRepo = 'Hoffnungsschimmers/cf-ip'`），改为 `= 'Hoffnungsschimmers/mnscn'`。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/core/config/app_config_test.dart`
Expected: PASS

---

### Task 4: 结果页「推送 GitHub」与「地址」按钮

**Files:**
- Modify: `lib/app/providers.dart`（新增 `githubPushProvider`）
- Modify: `lib/features/results/results_tab.dart`（按钮 + `_pushToGithub` + `_copyRawUrl`）
- Test: `test/features/results/results_tab_test.dart`（ResultsTab group 内加 3 个 widget 测试）

**Interfaces:**
- Consumes: `ResultState.toText()`（Task 2）；`GithubPush(token:, repo:, branch:, sender:)` 与 `pushFile(path, content, {message})`（`lib/core/github/github_push.dart`）
- Produces: `githubPushProvider`（`Provider<GithubPush Function(AppConfig)>`，定义于 `lib/app/providers.dart`）

- [ ] **Step 1: 写失败测试**

在 `test/features/results/results_tab_test.dart` 的 `group('ResultsTab')` 内追加：

```dart
    Future<void> pumpResultsTab(
      WidgetTester tester, {
      required ProviderContainer container,
    }) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: ResultsTab()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('地址按钮复制 raw 地址到剪贴板', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final container = ProviderContainer(overrides: [
        configProvider.overrideWith((ref) async => const AppConfig(
              subOutputFile: 'addressesapi.txt',
              githubRepo: 'Hoffnungsschimmers/mnscn',
              githubBranch: 'main',
            )),
      ]);
      addTearDown(container.dispose);
      await pumpResultsTab(tester, container: container);

      await tester.tap(find.widgetWithText(OutlinedButton, '地址'));
      await tester.pump();

      final setData = calls.firstWhere((c) => c.method == 'Clipboard.setData');
      expect((setData.arguments as Map)['text'],
          'https://raw.githubusercontent.com/Hoffnungsschimmers/mnscn/refs/heads/main/addressesapi.txt');
    });

    testWidgets('推送按钮成功后提示并完成 API 调用', (tester) async {
      final apiCalls = <String>[];
      Future<Response<dynamic>> fakeSender(RequestOptions o) async {
        apiCalls.add('${o.method} ${o.path}');
        if (o.path.startsWith('/user')) {
          return Response<dynamic>(statusCode: 200, requestOptions: o, data: <String, dynamic>{});
        }
        if (o.method == 'GET') {
          throw DioException(requestOptions: o,
              response: Response<dynamic>(statusCode: 404, requestOptions: o));
        }
        return Response<dynamic>(statusCode: 201, requestOptions: o, data: <String, dynamic>{});
      }

      final container = ProviderContainer(overrides: [
        configProvider.overrideWith((ref) async => const AppConfig(
              subOutputFile: 'addressesapi.txt',
              githubToken: 'ghp_test',
              githubRepo: 'Hoffnungsschimmers/mnscn',
              githubBranch: 'main',
            )),
        resultProvider.overrideWith((ref) => ResultNotifier()
          ..setRows([ResultRow('1.2.3.4:443#US mia', '50.00 ms')], 'addressesapi.txt')),
        githubPushProvider.overrideWith((ref) => (cfg) => GithubPush(
              token: cfg.githubToken,
              repo: cfg.githubRepo,
              branch: cfg.githubBranch,
              sender: fakeSender,
            )),
      ]);
      addTearDown(container.dispose);
      await pumpResultsTab(tester, container: container);

      await tester.tap(find.widgetWithText(OutlinedButton, '推送 GitHub'));
      await tester.pumpAndSettle();

      expect(apiCalls, containsAll(['GET /user', 'GET /repos/Hoffnungsschimmers/mnscn/contents/addressesapi.txt', 'PUT /repos/Hoffnungsschimmers/mnscn/contents/addressesapi.txt']));
      expect(find.textContaining('推送成功'), findsOneWidget);
    });

    testWidgets('token 为空时提示且不发起推送', (tester) async {
      var builderCalled = false;
      final container = ProviderContainer(overrides: [
        configProvider.overrideWith((ref) async => const AppConfig(
              subOutputFile: 'addressesapi.txt',
              githubToken: '',
            )),
        resultProvider.overrideWith((ref) => ResultNotifier()
          ..setRows([ResultRow('1.2.3.4:443#US mia', '50.00 ms')], 'addressesapi.txt')),
        githubPushProvider.overrideWith((ref) => (cfg) {
              builderCalled = true;
              return GithubPush(token: 'x', repo: 'o/r', sender: (o) async => Response<dynamic>(statusCode: 200, requestOptions: o));
            }),
      ]);
      addTearDown(container.dispose);
      await pumpResultsTab(tester, container: container);

      await tester.tap(find.widgetWithText(OutlinedButton, '推送 GitHub'));
      await tester.pump();

      expect(builderCalled, isFalse);
      expect(find.textContaining('GitHub Token'), findsOneWidget);
    });
```

需要的额外 imports（追加到 `test/features/results/results_tab_test.dart` 头部）：

```dart
import 'package:cfnb_app/core/github/github_push.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
```

注意：测试文件现有 `ResultsTab` group 顶部已有 `SharedPreferences.setMockInitialValues({})` + repo 初始化写法；上述新测试直接 override provider，无需文件系统，可独立运行。

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/results/results_tab_test.dart`
Expected: FAIL（`githubPushProvider` 未定义；按钮不存在，`find.widgetWithText` 找不到）

- [ ] **Step 3: 实现**

**3a. `lib/app/providers.dart`**：新增 import 与 provider（文件顶部已有 `flutter_riverpod`、`core/config` 相关 import）：

```dart
import '../core/github/github_push.dart';
```

文件末尾追加：

```dart
/// GitHub 推送构造器（结果页推送按钮使用）。独立 Provider 便于测试注入
/// mock sender，避免真实网络请求。
final githubPushProvider =
    Provider<GithubPush Function(AppConfig)>((ref) => (cfg) => GithubPush(
          token: cfg.githubToken,
          repo: cfg.githubRepo,
          branch: cfg.githubBranch,
        ));
```

（若 `providers.dart` 尚未 import `AppConfig`，追加 `import '../core/config/app_config.dart';`。）

**3b. `lib/features/results/results_tab.dart`**：

- `_ResultsTabState` 加状态字段：

```dart
  bool _pushing = false;
```

- 操作行 `Wrap` 中、`if (rows.isNotEmpty) ...[` 块**之后**（导出按钮后面）追加两个按钮：

```dart
                        // 推送 GitHub
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: t.textDim,
                              side: BorderSide(color: t.border),
                              visualDensity: VisualDensity.compact),
                          onPressed: _pushing ? null : _pushToGithub,
                          icon: _pushing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.upload, size: 16),
                          label: const Text('推送 GitHub', style: TextStyle(fontSize: 13)),
                        ),
                        // 地址（复制 raw 地址）
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: t.textDim,
                              side: BorderSide(color: t.border),
                              visualDensity: VisualDensity.compact),
                          onPressed: _copyRawUrl,
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('地址', style: TextStyle(fontSize: 13)),
                        ),
```

- 类内（`_doExport` 之后）加两个方法：

```dart
  Future<void> _pushToGithub() async {
    if (_pushing) return;
    final cfg = ref.read(configProvider).valueOrNull;
    if (cfg == null || cfg.githubToken.trim().isEmpty) {
      AppToast.show(context, '请先在配置页填写 GitHub Token', success: false);
      return;
    }
    final st = ref.read(resultProvider);
    if (st.rows.isEmpty) {
      AppToast.show(context, '当前结果为空，无法推送', success: false);
      return;
    }
    final fileName =
        (st.currentFile ?? cfg.subOutputFile).split(RegExp(r'[\\/]')).last;
    setState(() => _pushing = true);
    try {
      final pusher = ref.read(githubPushProvider)(cfg);
      await pusher.pushFile(
        fileName,
        st.toText(),
        message: 'push from cfnb (${st.rows.length} nodes)',
      );
      if (!mounted) return;
      AppToast.show(context, '推送成功：$fileName');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '推送失败：$e', success: false);
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  void _copyRawUrl() {
    final cfg = ref.read(configProvider).valueOrNull;
    if (cfg == null) return;
    final st = ref.read(resultProvider);
    final fileName =
        (st.currentFile ?? cfg.subOutputFile).split(RegExp(r'[\\/]')).last;
    final url =
        'https://raw.githubusercontent.com/${cfg.githubRepo}/refs/heads/${cfg.githubBranch}/$fileName';
    Clipboard.setData(ClipboardData(text: url));
    AppToast.show(context, 'raw 地址已复制：$url');
  }
```

（`AppToast` 已由 `../widgets/common.dart` 提供；`Clipboard` 已由 `flutter/services.dart` 提供，两处 import 已存在。）

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/results/results_tab_test.dart`
Expected: PASS（含 3 个新测试）

- [ ] **Step 5: 全量验证**

Run: `flutter analyze && flutter test`
Expected: analyze 0 error；全部测试通过（现有 199 + 新增 ≈ 206）

---

## 自审记录

- Spec 覆盖：首页空白（Task 1）、推送按钮（Task 4）、地址按钮（Task 4）、默认仓库 mnscn（Task 3）、序列化复用（Task 2）、token 为空提示（Task 4 测试 3）✓
- 类型一致性：`githubPushProvider` 签名在 Task 4 定义与测试中一致；`ResultState.toText()` 在 Task 2 定义、Task 4 使用 ✓
- 无占位符 ✓
- 提交 git 步骤已省略，完成后询问用户是否提交。