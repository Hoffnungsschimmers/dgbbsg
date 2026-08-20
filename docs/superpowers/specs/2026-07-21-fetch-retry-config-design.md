# 汇总：订阅抓取/Latency 配置 UI 补全与合理默认值 设计

日期：2026-07-21
分支：`feat/subscription-latency-ux`（HEAD `fd9b029`）

## 目标
- 暴露全部订阅抓取配置（连接/总超时、重试次数、重试间隔、解析并发、是否解析域名、是否跳过证书）到 ConfigTab，供用户调整。
- 暴露全部延迟优选参数到 UI（已是大部分，本次确认补齐 if any）。
- 把 Dio 重试逻辑接通：根据 maxRetries + retryDelay（含 2× 指数退避）做多次重试，覆盖所有错误类型。
- 调覆盖默认值为「推荐配置」组合。
- 重排 ConfigTab 分区、按场景归类。

## 一、决策（已 5 问确认）
1. 范围 = **全部 UI 可调**。
2. 重试范围 = **全部错误都重试**。
3. 默认值 = **推荐配置**（见下）。
4. 布局 = **重构分区 + 重排**。

## 二、推荐配置默认值（同时调整）
维持现有 4 个订阅抓取字段：**`subFetchConnectTimeout` / `subFetchTimeout` / `subFetchMaxRetries` / `subFetchRetryDelay`**，已经存在于 `AppConfig` 模型中却未在 UI 暴露也未在 Dio 中真正使用。默认值对齐：
- `subFetchConnectTimeout = 10` (s) — 不变。
- `subFetchTimeout = 20` (s) — 不变（用于 Dio receive/send 默认上限）。
- `subFetchMaxRetries = 2` — 由 3 改为 2（代表再重试 2 次，共 3 次尝试）。
- `subFetchRetryDelay = 2.0` (s) — 改为 double（原是 int），第一次延迟 2s，第二次 4s（指数退避）。
- `subResolveWorkers = 32` — 不变。
- `subResolveDomain = true` — 不变。
- `subInsecure = false` — 不变。

延迟优选默认（不变）：
- `subLatencyMaxMs = 200`, `subLatencyTopN = 50`, `subLatencyTimeout = 3.0`, `subLatencyWorkers = 50`, `subLatencyProbes = 3`, `subLatencyMinSuccessRate = 0.34`。

## 三、Dio 重试实现（核心新增）
- 在 `lib/core/net/retry.dart` 新增纯函数：`Future<T> retry<T>(Future<T> Function() body, {required int maxRetries, required Duration initialDelay, Future<void> Function(Duration)? sleep})`。实现：第 N 次失败（第 N+1 次尝试）前 sleep `initialDelay * 2^attempt`（最多 60s 上限）。`sleep` 默认 `Future.delayed`（便于测试注入）。
- `subscriptions_state.dart`：把 `_safeFetch` 加 cfg 参数；内部 `_fetchWithRetry(dio, url, cfg)` 调 `retry(() async => dio.get(url, options: opts), maxRetries: cfg.subFetchMaxRetries, initialDelay: Duration(milliseconds: (cfg.subFetchRetryDelay * 1000).round()))`，opts 把 timeout/connectTimeout 从 cfg 接入。
- 多次重试期间日志提示「第 N 次重试（剩余 X）」（用 `_logBuf`/`onLog` 仅写 Info，不刷 UI）。
- 所有错误（包括 Dio 的 `badResponse/connectionTimeout/connectionError` 等）都重试，符合用户决策。

## 四、ConfigTab 重构分区
现有分区（高级参数 / 延迟优选设置卡片）拆为有序 5 个 card：
1. **订阅输入**：原「Subscription Mode」+ Generators + Urls + Host/UUID/Country + subResolveDomain 开关 + subConvertEnabled 开关。
2. **订阅抓取**（新）：subFetchConnectTimeout(slider 1-30, 整数)、subFetchTimeout(slider 5-60, 整数)、subFetchMaxRetries(slider 0-5, 整数)、subFetchRetryDelay(doubleSlider 0.1-10, 一位小数)、subResolveWorkers(slider 1-128, 整 数，默认 32)、subInsecure 开关。
3. **延迟优选**：maxMs / topN / minSuccessRate / timeout / workers / probes / SNI / outputFile（已大部分存在；本任务一并确认齐全）。
4. **GitHub 推送**：Token/Repo/Branch。
5. **外观与主题**：深色主题开关。

## 五、测试
- `retry_test.dart`：成功无需重试（直接返回）；第 N 次失败后第 N+1 次成功（返回成功结果）；maxRetries=0 不重试；指数退避的 delays（mock sleep，断言：attempts=0 失败 → sleep(2s)；attempts=1 失败 → sleep(4s)；attempts=2 失败 → sleep(8s)，但到 maxRetries 上限后停止并抛出最后异常）。
- `app_config_test.dart` 现有断言补充 `subFetchMaxRetries == 2`、`subFetchRetryDelay == 2.0`。

## 六、不改动项（YAGNI）
- 不引入新第三方依赖（`dart:async` 是 SDK）。
- 不改 DNS 并发（保持当前无并发）。
- 不改 Deio 长生命周期（Task 3 已做）。

## 风险
- 重试在公开源上可能触发风控（部分订阅器对短时间重试敏感）。故加日志、第 N 此开始提示，便于用户感知；如果某个源被风控退 4xx，重复重试会变慢。以用户决策为准，遵循"全部错误都重试"。
