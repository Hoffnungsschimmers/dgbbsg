# cfnb_app 全面优化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复抓取/去重/重建期的隐性 bug，降低多源抓取与回退耗时，提升转换器与结果页的可维护性。

**Architecture:** 以「有限并发 + race-first + 连接复用」改造抓取链路；用 `ip:port#cc` 去重；把 `ResultsTab`/`convertSubscriptions` 拆分为可测小单元；补齐单测。

**Tech Stack:** Flutter 3.44.6 / Dart 3.12.2；flutter_riverpod ^2.5.1；dio ^5.7.0；crypto；path_provider。`flutter build windows --release`（须先删 `build/windows` 强重建）。

## Global Constraints
- 分支：`feat/subscription-latency-ux`，基于 `b258248`；每次提交前 `flutter analyze` 0 error（3 条历史 info 级 lint 允许）。
- 不引入新第三方依赖。并发限流用自实现的 `Semaphore`（已有 `latency_prober.dart` 内 `_Semaphore` 可复用/抽取）。
- 输入框同步一律用 `_syncIf`/`_syncList` 差异守护。
- 配置项保持相对文件名，运行时解析到文档目录。

---

### Task 1: 抽取共用 IP 判定（S1） + 去重按 ip:port#cc（B1）

**Files:**
- Create: `lib/core/net/ip.dart`
- Modify: `lib/core/subscription/subscription_converter.dart`（用 `isIp`；改 `convertSubscriptions` 去重 key）
- Modify: `lib/features/subscriptions/subscriptions_state.dart`（用 `isIp`）
- Modify: `lib/core/latency/latency_prober.dart`（`_isIp` 调用点替换为共用，或保留本地但统一）
- Test: `test/core/net/ip_test.dart`（新建）

**Interfaces:**
- Produces: `bool isIp(String host)`、`bool isIpv6(String host)` in `lib/core/net/ip.dart`。

- [ ] **Step 1: 写失败测试** `test/core/net/ip_test.dart`：覆盖 IPv4（`1.2.3.4` true，`999.1.1.1` false，`1.2.3` false）、IPv6（`[::1]` / `2001:db8::1` true）、非 IP（`example.com` false、`C:\x` false）。
- [ ] **Step 2: 运行测试确认失败**（`flutter test test/core/net/ip_test.dart`）→ FAIL。
- [ ] **Step 3: 实现 `lib/core/net/ip.dart`**：从三处的 `_isIp` 抽成 `isIp`（含 IPv4 四段 0-255 + IPv6 十六进制冒号）、`isIpv6`（含方括号）。
- [ ] **Step 4: 改 `subscription_converter.dart`**：import `ip.dart`，`convertSubscriptions` 把 `seen.contains(ip)` 改为 `seen.contains('$ip:${r.port}#$cc')`（key 用最终 node 串），去重判定与 `nodes.add` 一致；`_isIp` 本地调用替换为 `isIp`。
- [ ] **Step 5: 改 `subscriptions_state.dart`**：`_isIp` 替换成 `isIp`（import `core/net/ip.dart`）。
- [ ] **Step 6: 运行测试 + analyze** 通过。
- [ ] **Step 7: 提交** `git commit -m "fix: 节点去重按 ip:port#cc，抽取共用 isIp"`

---

### Task 2: 源并发抓取 + race-first 回退（P1 + P2 + P3）

**Files:**
- Modify: `lib/core/subscription/subscription_converter.dart`（`convertSubscriptions` 并发、`fetchFirstWorking` 竞态、`resolveHosts` DNS 限流）
- Test: `test/core/subscription/subscription_converter_test.dart`（新建：并发耗时 < 串行、首源胜出、同 IP 多端口保留）

**Interfaces:**
- Consumes: `Semaphore`（自实现或复用 `_Semaphore`，放入 `lib/core/net/concurrency.dart` 共用）
- Consumes: Task 1 的 `isIp`、B1 去重 key

- [ ] **Step 1: 写测试** 注入 mock `SubFetcher`（不同延迟），断言：(a) 多源总耗时 < 各源延迟之和（并发生效）；(b) `fetchFirstWorking` 在首条成功即返回，不等最慢；(c) B1 同 IP 不同端口都保留。预期失败（当前串行）。
- [ ] **Step 2: 运行测试确认失败。**
- [ ] **Step 3: 抽取 `lib/core/net/concurrency.dart`**：`class Semaphore { Semaphore(this._count); ... }`（从 `latency_prober._Semaphore` 复制为公开共用）。
- [ ] **Step 4: `convertSubscriptions`**：把 `for (final (name, urls) in tasks)` 改为有限并发——`Future.wait(tasks.map((t) async { ... }))`，外层套 `Semaphore`（上限 `config.subResolveWorkers` 或 `subFetchWorkers`，默认 32）。每源内部仍调 `fetchFirstWorking`。
- [ ] **Step 5: `fetchFirstWorking`**：改为 race-first——用 `Completer<String>` + 每个 URL 完成即尝试 `SubParser.parseSubscriptionLinks`，首条能解析就 `complete` 并让其余结果被忽略（用 `Future.any` 包裹解析成功的 promise；无法原生取消则忽略后续）。保持「都没节点时返回首个非空兜底」。
- [ ] **Step 6: `resolveHosts`**：`Future.wait(hosts.map(resolve))` 改为带 `Semaphore`（默认 32）的并发。
- [ ] **Step 7: 运行测试 + analyze** 通过。
- [ ] **Step 8: 提交** `git commit -m "perf: 订阅源有限并发抓取 + race-first 回退 + DNS 限流"`

---

### Task 3: Dio 长生命周期 + 抓取异常分类（P4 + B5）

**Files:**
- Modify: `lib/features/subscriptions/subscriptions_state.dart`（`_makeDio` → 两实例 `_dioSafe`/`_dioInsecure`；`_safeFetch` 异常分类）
- Test: `test/features/subscriptions/safe_fetch_test.dart`（新建：mock DioExceptionType → 分类标签）

**Interfaces:**
- Consumes: `edgetunnelUa`（已有）、`AppLogger`

- [ ] **Step 1: 写测试** mock `SubFetcher` 抛 `DioException(type: connectionTimeout)` / `receiveTimeout` / `badResponse(statusCode:403)` / `unknown`，断言日志文案含可辨识分类（如「连接超时」「读取超时」「HTTP 403」「未知错误」）。
- [ ] **Step 2: 运行测试确认失败。**
- [ ] **Step 3: `subscriptions_state.dart`**：去掉 `_makeDio` 每次新建；在 `SubscriptionsNotifier` 构造时建 `_dioSafe = GithubPush.directDio()` 与 `_dioInsecure`（带 `badCertificateCallback` 跳过校验），`_httpFetch` 按 `certInsecure` 选实例。
- [ ] **Step 4: `_safeFetch`**：catch 块按 `e is DioException` 的 `.type` 分支生成 `hint`/主消息（超时/状态码/无网络/未知），保留原有 403+BEST_SUB 提示。
- [ ] **Step 5: 运行测试 + analyze** 通过。
- [ ] **Step 6: 提交** `git commit -m "perf/fix: Dio 连接复用 + 抓取异常分类"`

---

### Task 4: ResultsTab 重建副作用与结构拆分（B2 + S2）

**Files:**
- Modify: `lib/features/results/results_tab.dart`（用 `ref.listen` 替代 build 内触发；拆 `ResultStatsRow`/`ResultTable`/`PushGithubButton` 子组件）

**Interfaces:**
- Consumes: `resultProvider`、`configProvider`、`subProvider`、`resolveOutputPath`（已有）、`AppButton`/`card`/`sectionTitle`（common.dart）

- [ ] **Step 1: 移除 `build` 内 `_lastCfgKey` diff + `_refreshCandidates` 调用**，改为 `initState` 里 `ref.listen(configProvider, (_, next) => _refreshCandidates(next.value))` 并在 `initState` 先调一次；保留 `_refreshCandidates` 自身（仍解析到文档目录）。
- [ ] **Step 2: 把统计卡 `_stat`/`_bestSpeed`(已删)/分布 Chip/表格 `_th`/`_td` 抽成无状态子组件 `ResultStatsRow`（行）/ `ResultTable`（表），GitHub 推送按钮抽成 `PushGithubButton`（保留 `_pushing` 状态于自身）。`ResultsTab` 只做编排与 `DropdownButton`/`ToggleButtons` 选区。
- [ ] **Step 3: analyze 0 error；`flutter test` 通过（结果页无专属 widget 测试则靠全量）。**
- [ ] **Step 4: 提交** `git commit -m "refactor: ResultsTab 用 ref.listen + 拆子组件"`

---

### Task 5: 小边界 Bug 与日志节流（B3 + B4 + P5）

**Files:**
- Modify: `lib/features/widgets/common.dart`（`labeledDoubleSlider` divisions clamp）
- Modify: `lib/core/config/app_config.dart`（`resolveOutputPath` 盘符判定）
- Modify: `lib/core/latency/latency_prober.dart`（`latencyProbeAll` 的 `onLog` 批量/`microtask`）

**Interfaces:**
- Consumes: Task 1 的 `isIp` 已就绪（本任务不涉及）

- [ ] **Step 1: common.dart `labeledDoubleSlider`**：`divisions: ((max - min) * 10).round().clamp(1, 1<<30)`；若 min==max 则 `divisions` 传 null。
- [ ] **Step 2: app_config.dart `resolveOutputPath`**：isAbs 正则 `^[a-zA-Z]:[\\/]` → `^[a-zA-Z]:`（带冒号即绝对），避免裸 `C:` 误判相对。
- [ ] **Step 3: latency_prober.dart `latencyProbeAll`**：`onLog` 每节点调用改为累计到 buffer，每 N 个或每 ~200ms flush 一次（用 `Timer` 或 `Future.microtask` 合并），避免几千节点同步刷 UI。
- [ ] **Step 4: analyze 0 error + 全量 test 通过。**
- [ ] **Step 5: 提交** `git commit -m "fix: 滑块/路径边界 + 延迟日志节流"`

---

### Task 6: 主题开关恢复（B6）

**Files:**
- Modify: `lib/features/subscriptions/config_tab.dart`（顶部加主题切换开关）

**Interfaces:**
- Consumes: `themeModeProvider`（main.dart 已 `ref.watch`）、`labeledSwitch`（common.dart）

- [ ] **Step 1: 在 `ConfigTab` build 顶部（首个卡片前或「高级参数」卡片内）加 `labeledSwitch(context, '深色主题', ref.watch(themeModeProvider) == ThemeMode.dark, (v) => ref.read(themeModeProvider.notifier).state = v ? ThemeMode.dark : ThemeMode.light)`。**
- [ ] **Step 2: analyze 0 error + 全量 test 通过。**
- [ ] **Step 3: 提交** `git commit -m "feat: ConfigTab 恢复深色主题切换开关"`

---

### Task 7: 全量验证（analyze + test + Windows 构建）

**Files:** 无新建

- [ ] **Step 1: `flutter analyze`** → 0 error（允许 3 条历史 info）。
- [ ] **Step 2: `flutter test`** → 全部通过。
- [ ] **Step 3: 杀掉占用 exe → 删 `build/windows` → `flutter build windows --release`** 成功。
- [ ] **Step 4: 若有补丁则提交；否则仅记录。Android APK 仍受本机无外网限制，标注需在能连 Google Maven 的环境构建验证（T2）。**
