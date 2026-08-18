# CF 优选代码加固实施计划（功能不变）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变任何用户可见功能的前提下，修复安全/正确性缺陷、删除死代码、统一设计系统、补齐测试，使 257 个测试保持通过。

**Architecture:** 保持现有分层（app/core/features/widgets）。策略：先修安全与正确性（小改动高价值），再大块删除死代码（顺带消解代码重复），然后统一设计系统，最后补测试。

**Tech Stack:** Flutter 3.44 / Dart 3.12 / flutter_riverpod / dio。构建命令：`flutter analyze`、`flutter test`（flutter 位于 `D:\env\flutter\bin`，已在 PATH）。

## Global Constraints

- **功能冻结**：不添加任何新功能/新 UI 控件/新用户选项。只修复缺陷、删除死代码、统一内部实现。
- 删除死代码前必须先 grep 确认无生产调用（测试引用不算，测试随代码一起删）。
- 每任务结束必须 `flutter analyze`（0 error）且 `flutter test` 全绿（基线 257 个）。
- 每任务独立 commit，风格 `fix:`/`refactor:`/`chore:` + 中文描述。
- 分支：`refactor/hardening`（基线 143b2e5 已提交）。
- 深色模式兼容：不得引入新的硬编码 `Colors.orange/grey/red/green`，一律走 `AppThemeExt` 令牌。
- 手机端兼容：不得新增固定像素宽度的对话框/输入框。

---

## 阶段 1 — 安全修复

### Task 1.1: 修复 TLS 证书校验无条件绕过（S1）

**Files:**
- Modify: `lib/core/github/github_push.dart:36-52`（`_applySystemProxy`）
- Modify: `lib/features/subscriptions/subscriptions_state.dart:85-110`（`_dioSafe`/`_dioInsecure`）
- Test: `test/core/github/github_push_test.dart`

**问题：** `_applySystemProxy` 检测到系统代理时无条件设 `badCertificateCallback = true`，使所有订阅抓取流量可被代理 MITM，无视 `subInsecure` 配置。

**修复：** 给 `directDio` 加 `bool insecure` 参数（默认 false）；`_applySystemProxy(dio, insecure)` 仅在 `insecure` 时设置证书回调；`_dioInsecure` 直接 `GithubPush.directDio(insecure: true)`，删除适配器 hack（96-107 行）。

**关键代码：**
```dart
static Dio directDio({bool insecure = false}) {
  final dio = Dio(BaseOptions(...));
  _applySystemProxy(dio, insecure: insecure);
  return dio;
}

static void _applySystemProxy(Dio dio, {bool insecure = false}) {
  final proxy = readSystemProxy();
  if (proxy == null) return;
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY $proxy';
      if (insecure) {
        client.badCertificateCallback = (_, _, _) => true;
      }
      return client;
    };
  }
}
```

- [ ] 步骤 1: 修改 github_push.dart（`directDio({bool insecure = false})`）
- [ ] 步骤 2: subscriptions_state.dart `_dioSafe = GithubPush.directDio()`（不变），`_dioInsecure` 简化为 `GithubPush.directDio(insecure: true)`，删除 96-107 行适配器复用逻辑
- [ ] 步骤 3: `flutter analyze` + `flutter test`
- [ ] 步骤 4: commit `fix: 系统代理下仅 subInsecure=true 时跳过 TLS 证书校验`

### Task 1.2: 密钥明文存储改安全存储（S2）

**Files:**
- Modify: `lib/core/config/config_repository.dart`
- Modify: `pubspec.yaml`（新增 flutter_secure_storage）
- Test: `test/core/config/config_repository_test.dart`（新建）

**问题：** `githubToken`、`webhookUrl`（内嵌 Telegram bot token）明文存 SharedPreferences。

**修复：** 引入 `SecureKV` 抽象（读/写接口，生产实现用 flutter_secure_storage，测试注入内存实现）；ConfigRepository 构造接受 `SecureKV`；`githubToken`/`webhookUrl` 从主 JSON 中移除，改经 SecureKV 读写（AppConfig 字段保留，fromJson/toJson 跳过这两键）。

- [ ] 步骤 1: pubspec.yaml 添加 `flutter_secure_storage: ^9.2.2`，`flutter pub get`
- [ ] 步骤 2: 新建 `lib/core/config/secure_kv.dart`（抽象接口 + SecureStorageKv 实现）
- [ ] 步骤 3: config_repository.dart 接入 SecureKV（构造参数注入，providers.dart 提供实例）
- [ ] 步骤 4: 写测试 `test/core/config/config_repository_test.dart`（内存 fake 验证 token 走 SecureKV、其余走 prefs）
- [ ] 步骤 5: analyze + test + commit `fix: GitHub Token/Webhook URL 改安全存储`

## 阶段 2 — 正确性修复

### Task 2.1: 尾斜杠正则 bug（C5）

**Files:**
- Modify: `lib/core/subscription/subscription_converter.dart:100`
- Test: `test/core/subscription/subscription_converter_test.dart`

**问题：** `RegExp(r'/+\$')` 在 raw string 中 `\$` 是字面量，结尾斜杠永不剥离 → 双斜杠 URL 404。

**修复：** `RegExp(r'/+$')`。加测试：`generatorFetchUrls('https://sub.example.com/', cfg)` 生成的 URL 不含 `//sub`。

- [ ] 步骤 1: 先写失败测试
- [ ] 步骤 2: 修正则，测试通过
- [ ] 步骤 3: analyze + test + commit `fix: 订阅器结尾斜杠剥离正则失效导致双斜杠 URL`

### Task 2.2: 配置迁移版本化（C4）

**Files:**
- Modify: `lib/core/config/config_repository.dart:25-47`
- Test: `test/core/config/config_repository_test.dart`

**问题：** 无条件把 `subLatencyTopN==0`→50、`subLatencyMaxMs==0`→300、`subLatencyTimeout==2.0`→3.0，无版本号，销毁用户合法值（0=全部保留）。

**修复：** 加 `_kSchemaVersion = 1`；仅当存储版本 < 1 时执行旧迁移（一次性）；之后不再改写值。已有用户的值已在历史迁移中改写，无回滚需求。

- [ ] 步骤 1: 写测试（legacy JSON 无版本 → 迁移；有版本 v1 且 topN=0 → 保持 0）
- [ ] 步骤 2: 实现版本化迁移
- [ ] 步骤 3: analyze + test + commit `fix: 配置迁移加 schema 版本号，不再覆盖用户 0 值`

### Task 2.3: 推送成功后误报失败（C1）

**Files:**
- Modify: `lib/features/github_sync/github_sync_state.dart:239-252`
- Test: `test/features/github_sync/github_sync_state_test.dart`（新建）

**问题：** push 成功后拉取新 SHA 失败会落入 catch 报"推送失败"。

**修复：** SHA 刷新包独立 try/catch：
```dart
final code = await github.pushFile(file, content, message: ...);
var newSha = state.remoteSha;
try {
  final (_, sha) = await github.pullFile(file);
  newSha = sha;
} catch (e) {
  _log.warning('推送成功但刷新 SHA 失败：$e');
}
state = state.copyWith(pushing: false, remoteSha: newSha, message: '推送成功：...');
```
需要让 `GithubPush` 可注入（`_github(cfg)` 已存在，检查是否可测试注入；不可则加可选构造参数）。

- [ ] 步骤 1: 写测试（注入 fake：push 成功、pull 抛错 → state.error 为 null、message 含推送成功）
- [ ] 步骤 2: 实现修复
- [ ] 步骤 3: analyze + test + commit `fix: 推送成功后 SHA 刷新失败不再误报推送失败`

### Task 2.4: 结果加载三路径统一（C3）

**Files:**
- Modify: `lib/features/results/results_tab.dart:44-49, 213-219`
- Modify: `lib/app/app.dart:35-40`
- Test: `test/features/results/results_tab_test.dart`（已有，扩展）

**问题：** 启动时 `ref.read(configProvider).value` 必为 null（FutureProvider）→ 结果页永远空白直到手动刷新；刷新按钮读 `subOutputFile`、Ctrl+R 读 `subLatencyOutputFile`，互相矛盾。

**修复：** 统一规则：**所有路径加载 `state.currentFile ?? cfg.subOutputFile`**。
- 启动：`ref.listenManual(configProvider, ...)` 首次 data 时 `loadFile(state.currentFile ?? cfg.subOutputFile)`
- 刷新按钮：同上规则
- app.dart Ctrl+R：改为通知结果页刷新（或同样规则读 `resultProvider` 当前值）

- [ ] 步骤 1: 写 widget 测试（configProvider override 后 ResultsTab 自动加载文件）
- [ ] 步骤 2: 实现三路径统一
- [ ] 步骤 3: analyze + test + commit `fix: 结果页启动加载与刷新路径统一为当前文件`

### Task 2.5: 部分订阅源失败不暴露（C7）

**Files:**
- Modify: `lib/core/subscription/subscription_converter.dart:226-260, 292`
- Modify: `lib/features/subscriptions/subscriptions_state.dart:193-201`
- Test: `test/core/subscription/subscription_converter_test.dart`

**修复（最小化，无 UI 变化）：**
- `convertSubscriptions` 返回 `(节点列表, 成功源数, 失败源数)` 三元组（或记录类型）
- 完成日志增加失败源统计
- `runSubscription` 全失败时设 `state.error`（短消息）并输出明确日志

- [ ] 步骤 1: 改返回类型 + 测试适配
- [ ] 步骤 2: subscriptions_state 全失败设置 error
- [ ] 步骤 3: analyze + test + commit `fix: 订阅源失败数量暴露，全失败进入错误状态`

### Task 2.6: 平台守卫与死链接（C9+C10）

**Files:**
- Modify: `lib/main.dart:22-34, 54-90`
- Modify: `lib/app/system_tray.dart:19-27`
- Modify: `lib/features/onboarding/onboarding_wizard.dart:490-498`

**修复：**
- main.dart：桌面 API（windowManager/systemTray）加 `Platform.isWindows || Platform.isLinux || Platform.isMacOS` 守卫（Android/Web 跳过）
- system_tray 图标：改用 rootBundle 读 logo.png → 写入临时目录文件（勿依赖打包后不存在的 `assets/...` 文件系统路径）
- onboarding 假链接：InkWell 改纯 Text（不加 url_launcher 依赖，功能冻结）

- [ ] 步骤 1: main.dart 守卫 + system_tray 修复
- [ ] 步骤 2: onboarding 死链接改纯文本
- [ ] 步骤 3: analyze + test + commit `fix: Android 启动崩溃风险（平台守卫）+ 托盘图标路径 + 死链接清理`

## 阶段 3 — 死代码清理

每任务：grep 确认 → 删除 → analyze/test → commit。

### Task 3.1: scanner 子系统整目录删除
- 删除：`lib/core/scanner/`（scanner_state 753 行 / speed_test 207 / cf_range_scanner 94 / http_ping 61）
- 删除：`test/core/scanner/`（3 个测试文件）
- 删除：`lib/core/config/app_config.dart` 中 8 个 `scanner*` 字段（field/default/fromJson/toJson/copyWith 各 8 处）
- 适配：`app_config_test.dart` 中引用 scanner 字段的断言
- commit: `refactor: 删除未接入的 scanner 扫描子系统（约 1100 行）`

### Task 3.2: config_generator.dart 整文件删除
- 删除：`lib/core/export/config_generator.dart`（422 行）+ `test/core/export/config_generator_test.dart`
- 检查：result_exporter.dart 的 `_parseIpPort/_detectProtocol/_buildEntries` 保留（重复自动消解）
- commit: `refactor: 删除死代码 config_generator（Clash 导出走 ResultExporter）`

### Task 3.3: widgets 死文件删除
- 删除：`lib/features/widgets/probe_dashboard.dart`（442）、`geo_chip.dart`（41）、`lib/features/results/results_stats.dart`（74）、`form_widgets.dart`（47）
- 清理：`lib/features/widgets/common.dart` barrel export
- 清理：`test/features/widgets/common_test.dart` 中 GeoChip/labeled* 测试组
- commit: `refactor: 删除未实例化组件（ProbeDashboard/GeoChip/ResultStatsRow/form_widgets）`

### Task 3.4: latency_prober MultiPort 死函数
- 删除：`measureLatencyMultiPort`、`latencyProbeAllMultiPort`（latency_prober.dart:264-351 区域）
- 删除：`test/core/latency/latency_multiport_test.dart`
- commit: `refactor: 删除未使用的多端口探测函数`

### Task 3.5: ip.dart 死函数
- 删除：`countryCodeToFlag`、`normalizeCountryCode`、`geolocateIpBatch`、`geolocateIpFallback`、`geolocateCfIp`（在 T3.1 后确认无调用者）
- 保留：`geolocateCfIpBatch`（latency_filter 在用）、`cfAirportToCountry`、`countryCodeToName`
- 删除：`subscription_converter.dart` 中 `convertSubscriptions` 的 `geolocateIps/geolocateIpsFallback` 注入参数（无人传）
- commit: `refactor: 删除 ip.dart 死函数与遗留注入参数`

### Task 3.6: result_state 死过滤器（C2）
- 删除：`filterCountry/filterMaxLatency/filterMaxJitter` 字段、3 个 setter；`filteredRows` 仅 searchQuery
- 适配：`test/features/results/result_state_test.dart`
- commit: `refactor: 删除未生效的结果过滤器字段`

### Task 3.7: subscriptions_state 进度管线（C8）
- 删除：`LatencyProgress`、`LatencySummary`、`state.progress`、`lastResult`、runLatency 内节流块（221-234/266-280）
- 适配：`SubscriptionsState`/`copyWith`（含 clearProgress/clearResult 参数）
- commit: `refactor: 删除从未渲染的延迟进度管线（run_tab 只用 running/currentAction）`

### Task 3.8: AppFailure 层级删除（M3）
- 删除：`lib/core/error/app_failure.dart` + `test/core/error/app_failure_test.dart` + 空目录
- commit: `refactor: 删除未使用的 AppFailure 异常层级`

### Task 3.9: file_picker 依赖移除（M1）
- 修改：`pubspec.yaml` 删除 file_picker；`flutter pub get`；如有 pubspec.lock 变更一并提交
- commit: `chore: 移除未使用的 file_picker 依赖`

## 阶段 4 — 共享代码与删除确认

### Task 4.1: 表格共享逻辑抽取
- 新建：`lib/features/results/node_edit_dialog.dart` — `Future<(String ipPort, String? latency, String? source)?> showNodeEditDialog(BuildContext, {String ipPort, String? latency, String? source, required String title})`（由 results_tab 与 github_sync_tab 共用）
- 新建：`lib/features/widgets/empty_state.dart` — `emptyState(BuildContext, {required IconData icon, required String title, required String subtitle})` 空状态卡片（两 tab 共用）
- 修改：results_tab.dart / github_sync_tab.dart 删除本地 `_showEditDialog`/空状态内联，改调用共享
- `_sortRows` 保留各 tab 本地（列不同，抽取收益低）
- commit: `refactor: 抽取两 tab 共用的节点编辑对话框与空状态组件`

### Task 4.2: 删除操作确认对话框
- 修改：`lib/features/results/results_tab.dart:407-421` — 删除前 showDialog 确认
- 修改：`lib/features/github_sync/github_sync_tab.dart:370-377`
- 修改：`lib/features/subscriptions/config_tab.dart:271-274, 360-363`（generator/URL 删除）
- 修改：`lib/features/onboarding/onboarding_wizard.dart:331`（generator 删除）
- 建议加 `lib/features/widgets/confirm_dialog.dart`：`Future<bool> confirmDelete(BuildContext, {required String title, required String message})`
- commit: `feat: 删除操作前增加确认对话框（节点/URL/订阅器）`

## 阶段 5 — 设计系统统一

### Task 5.1: 颜色与圆角令牌（item 7/8）
- `theme.dart`：`AppThemeExt` 增加 `radiusSm = BorderRadius.circular(8)`、`radiusXs = BorderRadius.circular(4)`
- config_tab.dart:135/138/143 三处 `Colors.orange*` → `t.warning`（背景 alpha 0.12 / icon / text 用 warning 派生色）
- 替换 14×`circular(8)`→`t.radiusSm`、6×`circular(4)`→`t.radiusXs`（pills 的 999 与 12/10/20/6 保留）
- commit: `refactor: 统一圆角令牌与警示色令牌`

### Task 5.2: 输入框样式统一（item 6）
- 删除 config_tab.dart `_compactTextField`（560-601），改用主题 InputDecorationTheme 或 `t.radiusSm`
- 统一 18 处内联 `InputDecoration`：fill 统一 `t.bg`（与全局主题一致），radius 统一 12 或 Sm
- commit: `refactor: 输入框样式统一到 InputDecorationTheme`

### Task 5.3: TextTheme 启用（item 5，最大工作量）
- `theme.dart`：AppThemeExt 增加语义文字 getters：`textTitle/textBody/textCaption/textDim/textMono`（复用既有 slot 或新增组合）
- 逐文件替换 76 处裸 `TextStyle(fontSize: N)`（config_tab 20 / onboarding 15 / results_tab 7 / github_sync 6 / sliders 4 / app 2 / pills 2 / run_tab 1 / cards 1 / section_collapsible 1）
- 按文件分批 commit（每批 1-2 个文件）
- commit: `refactor: 文字样式接入 TextTheme 令牌（第 N 批）`

### Task 5.4: 断点统一（item 16）
- toast.dart:103 `720` → `formFactorOf(MediaQuery.sizeOf(context).width)` 判 wide（expanded）
- results_tab.dart:143 / github_sync_tab.dart:187 `1100/1080` → 常量 `LayoutTokens.maxContentWidth = 1080`
- onboarding_wizard.dart:107 内联 600 → `Breakpoints.medium`
- commit: `refactor: 断点统一到 breakpoints.dart`

### Task 5.5: Motion 令牌（item 12）
- config_tab.dart:106 `200ms` → `Motion.saveDebounce`（300ms）
- log_view.dart:93 `80ms` → 新增 `Motion.logFlushTick = Duration(milliseconds: 80)`
- latency_prober.dart:148 `120ms` → `Motion.throttleTick`（60ms，纯日志节流无感）
- commit: `refactor: 硬编码时长统一到 Motion 令牌`

### Task 5.6: 命名统一（item 17）
- 重命名：`_batchToggleChip`→`_buildBatchToggleChip`、`_compactTextField`（T5.2 已删）`_exportButton`→`_buildExportButton`、`_emptyState`→`_buildEmptyState`、`_pushGithubButton`→`_buildPushGithubButton`
- commit: `refactor: widget builder 方法统一 _buildXxx 命名`

### Task 5.7: AppConfig 子模型分组（item 18）
- 新建子模型类（同文件或分文件）：`SubFetchConfig`（抓取 4 字段）、`LatencyConfig`（7 字段）、`GithubConfig`（3）、`WebhookConfig`（4）、`AutoUpdateConfig`（3）、`SubInputConfig`（9）
- `AppConfig` 字段改为持有子模型；fromJson/toJson/copyWith 每子模型 ~15 行
- 适配 `config_repository.dart`（迁移逻辑引用的字段路径）+ `app_config_test.dart`
- commit: `refactor: AppConfig 字段按域分组为子模型`

### Task 5.8: 国家码映射独立数据文件（item 18）
- 新建 `lib/core/net/country_data.dart`：迁移 `_countryNameMap`（104 条）+ `_cfAirportMap`（197 条）+ 访问函数
- ip.dart 改 import；消费者不变（同步调用，保持源码文件而非 asset——异步加载会破坏同步 parse 链）
- commit: `refactor: 国家码/机场映射表独立为数据文件`

## 阶段 6 — 性能与响应式

### Task 6.1: results_table 性能（item 10）
- `MediaQuery.of(context)` → `MediaQuery.sizeOf`
- `itemExtent` 删除，改 `prototypeItem`（修两行注释裁剪，M4）
- `.animate()` 行动画：列表 > 200 行时跳过动画（stagger 只对前 N 行）
- commit: `perf: 结果表 MediaQuery.sizeOf + 行高自适应 + 大列表跳过入场动画`

### Task 6.2: log_view 渲染（item 10）
- TextSpan 区域加 `RepaintBoundary`；样式分支合并（同色相邻行合并 span 需保 selection，若实现复杂则仅加 RepaintBoundary）
- 评估 2000 行上限保持（虚拟化会破坏整体选择）
- commit: `perf: 日志视图 RepaintBoundary 隔离重绘`

### Task 6.3: 响应式（item 11）
- config_tab.dart:617 批量粘贴对话框 `SizedBox(width: 500)` → `SizedBox(width: min(500, MediaQuery.sizeOf(context).width - 48))`（或用 constraints）
- results_tab.dart:183 搜索框 `SizedBox(width: 220)` → Wrap 内 `ConstrainedBox(maxWidth: 220)` + 窄屏伸展
- `_buildNodeParams`/抓取/GitHub 两列 Row → `LayoutBuilder`：宽度 < 600 时降级单列
- commit: `fix: 窄屏适配（批量粘贴对话框/搜索框/两列参数降级）`

## 阶段 7 — 可访问性

### Task 7.1: 语义与触控目标（item 13）
- `_batchToggleChip`（config_tab 463-478）：加 `Semantics(selected: ..., label: ...)` 或 check 图标
- CountUpText：包 `ExcludeSemantics`，动画结束后显示语义文本
- 触控目标：results_table 编辑/删除 IconButton `kIsMobile ? 48 : 32` → 桌面 40；ToggleButtons `minHeight: 34`→40；`visualDensity.compact` 按钮 minSize 40
- commit: `feat: 语义标注与触控目标达标`

## 阶段 8 — 测试补强

### Task 8.1: subscriptions_state 测试
- 新建 `test/features/subscriptions/subscriptions_state_test.dart`：runSubscription 失败汇总 error、runLatency 简化行为、cancel 中断
- commit: `test: subscriptions_state 行为测试`

### Task 8.2: github_sync_state 测试（T2.3 若已建则扩展）
- push 成功/失败/未配置/SHA 刷新失败四场景
- commit: `test: github_sync_state 推送场景测试`

### Task 8.3: config_repository 测试（T1.2/T2.2 若已建则扩展）
- 迁移版本化、SecureKV 分离、roundtrip
- commit: `test: config_repository 迁移与存储测试`

### Task 8.4: 结果页 widget 测试（T2.4 扩展）
- 启动自动加载、删除确认弹窗出现
- commit: `test: results_tab 启动加载与删除确认`

---

## 收尾

- [ ] 全量 `flutter analyze`（0 error）+ `flutter test` 全绿
- [ ] `flutter build windows --release` 冒烟（可验证范围内）
- [ ] 更新 `PROJECT_CONTEXT.md`（当前状态/架构变化/遗留项）
- [ ] 汇总提交历史，向用户报告
