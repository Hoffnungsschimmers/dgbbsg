# 首页空白修复 + 结果页 GitHub 推送与地址复制

日期：2026-08-19

## 背景

用户报告两个问题：
1. 打开软件后首页（配置页）空白，必须切换到其他页再切回才会显示。
2. 需要在结果页添加「推送 GitHub」按钮，推送结果文件并生成 raw 地址；再添加一个「地址」按钮用于复制该地址。

## 问题 1：首页空白根因与修复

### 根因

`lib/app/app.dart` 的 `_TabStackState.initState`（L205-211）构建了淡入/滑动动画但从未启动：

```dart
_ctrl = AnimationController(duration: Motion.durBase, vsync: this)
  ..addStatusListener(_onStatus);
_curve = CurvedAnimation(parent: _ctrl, curve: Motion.curveStandard);
_buildAnimations(0);   // 没有 _ctrl.forward() 或 _ctrl.value = 1.0
```

`_buildAnimations` 中 `_newFade = Tween(begin: 0.0, end: 1.0).animate(_curve)`，而 `AnimationController` 初始 value 为 0.0。首帧当前 tab 被包在 `FadeTransition(opacity: _newFade)` 中，opacity = 0 → widget 已构建但完全透明，表现为首页空白。只有切换 tab 时 `didUpdateWidget` 才 `_ctrl.forward(from: 0)`（L244），所以"换页才加载出来"。

### 修复

`initState` 在 `_buildAnimations(0)` 后补 `_ctrl.value = 1.0`，首帧直接处于动画完成态（透明度 1）。切换动画逻辑不变。

### 测试

Widget 测试：pump `AppShell`（或经 `ProviderScope` 包裹的 `_TabStack`），断言首帧当前 tab 的 `FadeTransition.opacity == 1.0` 且配置页可见（例如 `find.byType(ConfigTab)` 命中且 opacity 为 1）。

## 问题 2：结果页推送 GitHub + 地址复制

### 目标

- 结果页操作行新增「推送 GitHub」按钮：将当前结果页内容（节点行序列化文本）推送至 `Hoffnungsschimmers/mnscn` 仓库根目录、配置的分支（默认 main）。
- 新增「地址」按钮（始终可用）：点击复制 raw 地址 `https://raw.githubusercontent.com/{githubRepo}/refs/heads/{githubBranch}/{fileName}` 到剪贴板。
- 配置默认仓库从 `Hoffnungsschimmers/cf-ip` 改为 `Hoffnungsschimmers/mnscn`。

### 组件与数据流

1. **序列化**：`lib/features/results/result_state.dart` 提取 `ResultState.toText()` 方法（每行 `node` + latency，空格分隔，`writeln`），`ResultNotifier.saveToFile` 复用该方法，推送也使用该方法。

2. **推送按钮**（`lib/features/results/results_tab.dart` 操作行，导出按钮旁）：
   - 点击调用 `_pushToGithub()`：
     - 读取 `ref.read(configProvider).value`；为空或 `githubToken` 为空 → `AppToast` 提示"请先在配置页填写 GitHub Token"。
     - 结果为空（`state.rows` 空）→ `AppToast` 提示"当前结果为空，无法推送"。
     - 文件名 = `state.currentFile` 的文件名部分（`split(RegExp(r'[\\/]')).last`）；currentFile 为空时回退 `cfg.subOutputFile`。
     - `GithubPush(token: cfg.githubToken, repo: cfg.githubRepo, branch: cfg.githubBranch).pushFile(fileName, content, message: 'push from cfnb (N nodes)')`。
     - 成功 → `AppToast` 提示成功；失败（Exception/DioException）→ `AppToast` 显示错误信息。
     - 推送过程中按钮禁用（本地 bool state，`setState`）。
   - 按钮样式：`FilledButton.icon(Icons.upload, '推送 GitHub')`。

3. **地址按钮**（操作行，推送按钮旁）：
   - 始终可用。点击复制 `https://raw.githubusercontent.com/{cfg.githubRepo}/refs/heads/{cfg.githubBranch}/{fileName}`（fileName 同上），`Clipboard.setData` + `AppToast` 提示"地址已复制"。
   - 按钮样式：`OutlinedButton.icon(Icons.link, '地址')`。

4. **配置默认值**：`lib/core/config/app_config.dart` L35 `githubRepo` 默认改为 `'Hoffnungsschimmers/mnscn'`。

### 错误处理

- 推送失败统一 catch 并 toast 具体错误（沿用 `github_sync_tab` 的展示风格）。
- GitHub API 直连（GithubPush 构造已实现 DIRECT），不受本地代理影响。

### 测试

- 地址按钮：pump ResultsTab（ProviderScope + mock config/result），点击「地址」，断言 `Clipboard.getData` 内容为预期 raw 地址。
- 推送按钮：`GithubPush(sender: mock)` 注入（构造 `GithubPush` 时传 `sender` 参数模拟响应），点击推送，断言调用路径（GET /user、GET contents 404、PUT）及成功提示；token 为空时提示且不发起请求。

## 范围

- 不修改同步页（github_sync_tab）现有推送行为。
- 不引入第三方依赖（复用 dio / Clipboard / AppToast）。
- 分支与仓库均来自现有配置字段，用户可在配置页修改。