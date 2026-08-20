# 订阅器页面整合 + Android 适配 设计

日期：2026-07-19
分支：`feat/subscription-latency-ux`（基于 `main` 8723274）
前置：上一轮已把延迟优选简化为纯 TCP 延迟排序，移除带宽测速子系统。

## 目标

1. 把「设置」页合并进「订阅器」页，App 改为**单页 + 底部 Tab（配置 / 运行 / 结果）**。
2. 全面审查并修复上一轮带宽移除后残留的死代码与 bug（结果表带宽/质量分、setting_fields、appDirProvider 等）。
3. 删除重复的配置控件 helper，统一到 `features/widgets/common.dart`。
4. 从结构上为 Android 端打包做准备：Manifest 权限、明文流量、输出文件路径改为文档目录。

## 一、导航架构重构

- 修改 `lib/app/app.dart`：
  - 删除 `PageKey.settings` 与 `SettingsPage` 引用。
  - `AppShell` 改为单页 `Scaffold` + 底部 `NavigationBar`，三个 `NavigationDestination`：
    - 配置（`Icons.tune`）→ `ConfigTab`
    - 运行（`Icons.play_arrow`）→ `RunTab`
    - 结果（`Icons.bar_chart`）→ `ResultsTab`
  - 宽屏（`MediaQuery.size.width >= 720`）保留响应式：左侧窄导航栏 + 右侧内容（沿用现有 `_Sidebar` 思路，但只列 3 个 Tab）。
  - 删除 `_BottomNav`/`_Sidebar` 中 settings 项。
- 新增文件 `lib/features/home/home_page.dart` 作为单页壳，内含 `TabController` + 三个 Tab 子组件；或直接在 `app.dart` 内用 `IndexedStack` + `NavigationBar`。**采用**：在 `app.dart` 内实现 `AppShell`，三个 Tab 组件分别来自：
  - `lib/features/subscriptions/config_tab.dart`（配置）
  - `lib/features/subscriptions/run_tab.dart`（运行）
  - `lib/features/results/results_tab.dart`（结果，由现有 `ResultsPage` 改名而来）

## 二、配置 Tab（合并设置 + 订阅器设置）

- 新建 `lib/features/subscriptions/config_tab.dart`，把现有 `SubscriptionsPage` 中**纯配置部分**（输入模式/订阅器列表/订阅链接/Host/UUID/国家码/解析域名/启用订阅转换 + 延迟优选参数 + GitHub 推送）重组为分区卡片：
  - 卡片「订阅器输入」：`subInputMode` 分段、`subGenerators` 列表、`subUrls` 列表、`subNodeHost`、`subNodeUuid`、`subDefaultCountry`、`subResolveDomain`、`subConvertEnabled`。
  - 卡片「延迟优选」：`subLatencyMaxMs`、`subLatencyTopN`、`subLatencyMinSuccessRate`、`subLatencyTimeout`、`subLatencyWorkers`、`subLatencyProbes`、`subLatencySni`、`subInsecure`、`subLatencyOutputFile`。
  - 卡片「GitHub 推送」：`githubToken`（密码框）、`githubRepo`、`githubBranch`。
- 复用/统一控件：把 `_textField`/`_switchRow`/`_slider`/`_doubleSlider`/`_text`/`_dec` 等 helper 提升到 `features/widgets/common.dart`（去重，原 `settings_page.dart` 里的重复实现删除）。
- `_syncIf` 差异守护保留（修复输入框全选 bug）。列表型（`_genCtl`/`_urlCtl`）仍用 `_syncList` 守护。
- 删除 `lib/features/settings/settings_page.dart` 与 `lib/features/settings/settings_fields.dart`（后者为死代码，且仍引用已删 speed 字段）。

## 三、运行 Tab

- 新建 `lib/features/subscriptions/run_tab.dart`：
  - 顶部两个按钮：「订阅IP」(`runSubscription`)、「延迟优选」(`runLatency`)，沿用 `subProvider`。
  - 下方 `LogView`（沿用 `subLoggerProvider` + `common.dart` 的 `LogView`）。
  - 去掉原桌面侧边日志宽栏（`_logWidth`/`_logCollapsed`），移动端改为整页日志区。

## 四、结果 Tab

- `lib/features/results/results_page.dart` 重命名为 `results_tab.dart`，类 `ResultsPage`→`ResultsTab`，去掉 `Scaffold`/`AppBar` 外壳（由 `AppShell` 统一提供），内部 `Column` 直接作为 Tab 内容。
- **修复结果表 bug**：上一轮移除带宽后，`ResultRow.speed`/`ResultRow.quality` 已无数据来源，结果表仍显示「带宽/质量分」空列、`_bestSpeed`/`_bestQuality` 恒为 `—`。
  - `result_state.dart`：`ResultRow` 删除 `speed`/`quality` 字段及 `loadMap` 的 speed 用法；`parseResultLines` 仅解析 `节点` 与 `延迟`（保留对旧格式 `... 50.00 ms` 的兼容解析，忽略 Mbps/Q）。
  - `results_tab.dart`：表格列改为 **节点 / 延迟 / 国家**；统计卡改为 节点数 / 来源数 / 最低延迟；删除 `_bestSpeed`/`_bestQuality`/`bestSpeed()`/`bestQuality()` 相关死代码。

## 五、Android 适配

- `android/app/src/main/AndroidManifest.xml`：
  - `<manifest>` 内加 `<uses-permission android:name="android.permission.INTERNET" />` 与 `ACCESS_NETWORK_STATE`。
  - `<application android:usesCleartextTraffic="true" ...>`（允许 http 订阅源与裸 TCP 探测）。
- 输出文件路径：在 `subscriptions_state.dart` 与 `result_state.dart` 解析文件时，把相对文件名拼接 `getApplicationDocumentsDirectory()`。
  - 新增 `Future<String> resolvePath(String name)` helper（在 `subscriptions_state.dart` 或 `app/providers.dart` 提供 `appDirProvider` 真正接入）。配置文件里仍存相对名（`addressesapi.txt` 等），运行时解析为文档目录绝对路径。
  - 删除未使用的 `appDirProvider` 或正式接入（二选一，采用：正式接入 `appDirProvider` 并由 `resolvePath` 使用）。

## 六、死代码 / Bug 清理清单

- 删除 `lib/features/settings/` 整个目录。
- 删除 `settings_fields.dart`（`normalizeDraft` 未被任何处使用）。
- `latency_filter.dart`：`_jsonEncode` 输出节点已不含 `speed_mbps`/`quality`（上轮已改），复查确认无残留。
- 统一控件 helper 到 `common.dart`，删除各页重复私有实现。
- `result_state.dart`：移除 `speed`/`quality` 残留。
- `app.dart`：移除 `PageKey.settings`、`SettingsPage` 引用、宽屏/窄屏导航里的设置项。

## 七、测试与验证

- `flutter analyze`：0 error（允许历史 info 级 lint）。
- 现有 `test/core/config/app_config_test.dart` 保持通过。
- `flutter test` 整体通过。
- 构建：`flutter build windows --release`（先删 `build/windows` 强重建）与 `flutter build apk --release` 均成功。
- 手测：三 Tab 切换正常；配置页编辑后保存生效；运行页按钮触发日志；结果页显示延迟/国家分布，无空带宽列。

## 风险

- 路径改为文档目录后，Windows 上旧的相对路径文件需重新生成（不影响新运行）。
- Android 真机需 `INTERNET` 权限，否则订阅抓取与 TCP 探测全部失败——必须在 Manifest 声明。
