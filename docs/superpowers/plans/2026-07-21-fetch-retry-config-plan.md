# 订阅抓取/Latency 配置 UI 补全 + 重试 + 合理默认值 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** ConfigTab 完整暴露订阅抓取+延迟优选参数；把 cfg 真正接入 Dio（含重试 + 指数退避）；调默认值为「推荐配置」组合。

**Architecture:** 抽 `core/net/retry.dart` 纯函数；`subscriptions_state.dart` 抽 `fetchWithRetry` 顶层函数，超时与重试由 cfg 传入；`config_tab.dart` 拆 5 个 card；测试覆盖重试逻辑与默认值。

**Tech Stack:** Flutter 3.44.6 / Dart 3.12.2。`flutter build windows --release`（删 `build/windows` 强重建）。

## Global Constraints
- 分支基线 `fd9b029`；每次提交前 `flutter analyze` 0 error（3 历史 info 允许）。
- 不引入新第三方依赖；`dart:async` 是 SDK。
- 字段类型变化 `subFetchRetryDelay: int → double` 需同步改 4 处（field/constructor/fromJson/toJson/copyWith）。
- `_safeFetch` 失败仍按 `classifyFetchError` 分类记日志。

---

### Task 1: 抽 `retry<T>` + 调 AppConfig 默认值

**Files:**
- Create: `lib/core/net/retry.dart`
- Modify: `lib/core/config/app_config.dart`
- Modify: `test/core/config/app_config_test.dart`
- Test: `test/core/net/retry_test.dart`（新建）

**Interfaces:**
- Produces: `Future<T> retry<T>(Future<T> Function() body, {required int maxRetries, required Duration initialDelay, Future<void> Function(Duration)? sleep})`.

- [ ] **Step 1: 写失败测试** `retry_test.dart`：4 个用例（成功不用重试 / 第 N 此失败后成功 / maxRetries=0 不重试且抛 / 指数退避序列）。`sleep` mock 记录 durations 不真睡。预期 FAIL。
- [ ] **Step 2: 跑测试确认失败**。
- [ ] **Step 3: 实现 `lib/core/net/retry.dart`**：`while(true){ try{return await body()} catch(e){ if(attempt>=maxRetries) rethrow; var d = initialDelay*(1<<attempt); if(d>60s) d=60s; await sleeper(d); attempt++;}}`. sleep 默认 `Future.delayed`.
- [ ] **Step 4: 改 `app_config.dart`**：`subFetchRetryDelay int → double`，默认 `2.0`；`subFetchMaxRetries 默认 3 → 2`。同步改 constructor/fromJson/toJson/copyWith。fromJson:`(pick('SUB_FETCH_RETRY_DELAY', 2.0) as num).toDouble()`; copyWith 加 `double? subFetchRetryDelay` 参数。
- [ ] **Step 5: 检查 `config_repository.dart`** 是否引用 `subFetchRetryDelay`：如 未用则无需改。
- [ ] **Step 6: 测试 + analyze 全绿**。
- [ ] **Step 7: 提交** `git commit -m "feat: 抽 retry(get), 调订阅抓取默认值为推荐配置"`。

---

### Task 2: `_safeFetch` 接 cfg + 重试

**Files:**
- Modify: `lib/features/subscriptions/subscriptions_state.dart`
- Modify: `test/features/subscriptions/safe_fetch_test.dart`

**Interfaces:**
- Produces: `Future<String> fetchHttpWithRetry({required dio_pkg.Dio dio, required String url, required int connectTimeoutSec, required int sendTimeoutSec, required int receiveTimeoutSec, required int maxRetries, required int retryDelayMs, required void Function(int attempt, Duration delay)? onRetry})`（顶层纯函数）。

**测试策略**：在测试里给测试 Dio（adbanced Dio 空 instance）的 httpClientAdapter 插入 顺序返回 `ResponseBody(sc:503)` ×2 + `sc:200`。构造 Dio mock 需 写 adapter impl extending BaseHttpClientAdapter。轻量化：使用 dio 的 IOHttpClientAdapter + 一个 `validateStatus` hook 让 Dio 在 expectations 下重试。这要看 dio API。为避免 adapter mock 复杂，**测试 fetchHttpWithRetry 纯函数时传入一个普通 Dio + 用 `mockWebServer`/controllers 较重。**轻量决定：另写一个不依赖 Dio 的内核函数 `Future<String> _doFetchStringWithRetry(Future<String> Function() body, ...)`,由 `fetchHttpWithRetry` 调用。在这种拆出下，测试只测 内核 `doFetchStringWithRetry` 重试时序/body 调用次数。`body` 是一个 mock function。
**最终决定**：拆出 `Future<T> withDioRetry<T>(Future<T> Function() body, {required int maxRetries, required int retryDelayMs, required void Function(int)? onAttempt})`，抽在 `lib/core/net/retry.dart` 顶部，**复用 retry 还调它外部**。一者以求最少打断。

为求 依然干净:拆出 `Future<String> fetchHttp(Dio dio, String url, {...})` 文件顶层；**该函数体调 `retry` 包 调 extern body** 赋值 保证 超时 opts。测试可以 mock Dio `:if opt==int.max 返回 503`，Dio 发送..另：可改为测试 困难时，去 测 `retry(...)` + 上层函数仅 smoke test。具体会出现 实施 subagent 依内容独立设计。

- [ ] **Step 1: 写测试**：`fetchHttpWithRetry` 的 mock 测试。短实施：使用 dio 内置 `dio.options.validateStatus = (s) => true` 与 adapter 实现营盘 mock 顺序返回。预期 subagent 选「增献 test adapter」以完成。
- [ ] **Step 2: 抽出并实现 fetchHttpWithRetry**：
  ```dart
  Future<String> fetchHttpWithRetry({
    required dio_pkg.Dio dio,
    required String url,
    required int connectTimeoutSec,
    required int sendTimeoutSec,
    required int receiveTimeoutSec,
    required int maxRetries,
    required int retryDelayMs,
    void Function(int attempt)? onRetry,
  }) async {
    Future<String> doGet() async =>
        (await dio.get<String>(url, options: dio_pkg.Options(
          responseType: dio_pkg.ResponseType.plain,
          headers: {'User-Agent': edgetunnelUa, 'Accept': '*/*'},
          connectTimeout: Duration(seconds: connectTimeoutSec.clamp(1, 300)),
          sendTimeout: Duration(seconds: sendTimeoutSec.clamp(1, 600)),
          receiveTimeout: Duration(seconds: receiveTimeoutSec.clamp(1, 600)),
        ))).data.toString();
    return retry(() => doGet(),
        maxRetries: maxRetries,
        initialDelay: Duration(milliseconds: retryDelayMs));
  }
  ```
- [ ] **Step 3: 改 `_safeFetch` 传 cfg + 调 重试**：
  ```dart
  Future<String> _safeFetch(String url, bool certInsecure, AppConfig cfg) async {
    final logger = ref.read(subLoggerProvider);
    final dio = certInsecure ? _dioInsecure : _dioSafe;
    try {
      return await fetchHttpWithRetry(
        dio: dio, url: url,
        connectTimeoutSec: cfg.subFetchConnectTimeout,
        sendTimeoutSec: cfg.subFetchTimeout,
        receiveTimeoutSec: cfg.subFetchTimeout,
        maxRetries: cfg.subFetchMaxRetries.clamp(0, 10),
        retryDelayMs: (cfg.subFetchRetryDelay * 1000).round(),
      );
    } catch (e) {
      logger.error('抓取失败 [$url]：${classifyFetchError(e, url)}');
      return '';
    }
  }
  ```
- [ ] **Step 4: 调用点调整**:`runSubscription` `(url) => _safeFetch(url, cfg.subInsecure)` → `(url) => _safeFetch(url, cfg.subInsecure, cfg)`。
- [ ] **Step 5: 测试 + analyze 全绿**。
- [ ] **Step 6: 提交** `git commit -m "perf/fix: 接入 cfg 与指数退避重试到订阅抓取"`。

---

### Task 3: ConfigTab 重构分区 + 补 UI

**Files:**
- Modify: `lib/features/subscriptions/config_tab.dart`

**Interfaces:**
- Consumes: Task 1 新字段、Task 1/2 重构后的 Dio。

- [ ] **Step 1**: 重排为 5 个 card 顺序：①订阅输入 (原 inputMode/generators/urls/host/uuid/country/resolveDomain/convertEnabled) ②订阅抓取 (subFetchConnectTimeout slider 1-30=int, subFetchTimeout slider 5-60=int, subFetchMaxRetries slider 0-5=int, subFetchRetryDelay doubleSlider 0.1-10=double, subResolveWorkers slider 1-128=int, subInsecure 开关) ③延迟优选 (已在) ④GitHub推送 ⑤外观 (深色主题)。
- [ ] **Step 2**: 验证变量名、helper、save 调用一致；若 subFetchTimeout slider divs1=1.
- [ ] **Step 3**: analyze 0 error、全量 test ≤69 *依赖 .
- [ ] **Step 4**: 提交 `git commit -m "feat: ConfigTab 重排分区并补全订阅抓取/延迟优选 UI"`。

---

### Task 4: 全量验证 + 重新打包 + 刷新快捷方式

- [ ] **Step 1**: `flutter analyze` 0 error。
- [ ] **Step 2**: `flutter test` 全绿。
- [ ] **Step 3**: 杀 cfnb_app 旧进程 + 删 `build/windows` + `flutter build windows --release` 成功。
- [ ] **Step 4**: WScript.Shell 重写 `C:\Users\2540\Desktop\CF优选.lnk` 指向新 exe。
