# cfnb_app 全面优化 设计

日期：2026-07-19
分支：`feat/subscription-latency-ux`（HEAD `b258248`）

## 目标
在不破坏现有 UX 的前提下，修复抓取/去重/重建期的隐性 bug，显著降低多源抓取与回退耗时，并提升结果页与转换器的结构可维护性。

## 一、性能（高 ROI）
- **P1 源并发抓取**：`subscription_converter.dart:convertSubscriptions` 现在的 `for (tasks)` 改为有限并发（`Future.wait` + `Semaphore`，默认上限 `subResolveWorkers` 或新 `subFetchWorkers=32`），把多源串行变为并发。
- **P2 race-first 回退**：`fetchFirstWorking` 用「首条能解析即返回」的竞态替代 `Future.wait` 等全部完成，慢源超时不再拖累整组。
- **P3 DNS 限流**：`convertSubscriptions` 的 `Future.wait(hosts.map(resolve))` 加 `Semaphore`（复用 `subResolveWorkers`，默认 32），避免几千域名瞬时打满系统 DNS。
- **P4 Dio 连接复用**：`subscriptions_state` 把 `_makeDio` 的「每请求新建」改为构造期一次性建好两个长生命周期 Dio（`_dioSafe`/`_dioInsecure`），按 `certInsecure` 选其一，保留 HTTP keep-alive。
- **P5 日志节流**：`latency_prober.dart` 的每节点 `onLog` 改为批量/`microtask` 异步发出，避免几千节点同步刷卡 UI。

## 二、正确性 / Bug
- **B1 节点去重按 `ip:port#cc`**：`convertSubscriptions` 现在的 `seen.contains(ip)` 会把同 IP 不同端口/不同国家折叠为一条，丢合法变体。去重 key 改为 `'$ip:${r.port}#$cc'`。
- **B2 `ResultsTab` build 副作用移出**：`results_tab.dart` 在 `build` 里按 `_lastCfgKey` diff 触发 `_refreshCandidates`，属 build 期副作用 + 异路径 `setState`。改用 `ref.listen(configProvider, ...)` 在 `initState` 注册，配置变更触发刷新，build 内纯读。
- **B3 `labeledDoubleSlider` divisions=0 边界**：`common.dart` 的 `((max-min)*10).round()` 在 min==max 时为 0，`Slider(divisions:0)` 崩溃。改用 `.clamp(1, 1<<30)`，min==max 时 divisions=null。
- **B4 `resolveOutputPath` 裸盘符误判**：`app_config.dart` isAbs 正则 `^[a-zA-Z]:[\\/]` 把裸 `C:` 当相对路径。改 `^[a-zA-Z]:`（带冒号即绝对）。
- **B5 抓取异常分类**：`_safeFetch` 现在把所有异常 `e.toString()` 混在一起。按 `DioExceptionType`（connectionTimeout/receiveTimeout/badResponse→状态码/unknown）分类，给针对性提示。
- **B6 主题开关恢复**：Task 6 删了 sidebar 的主题切换按钮，`themeModeProvider` 现在只读不写。在 `ConfigTab` 顶部加一个主题切换开关（绑 `themeModeProvider.notifier`），恢复丢失的 UX。

## 三、结构 / 可维护性
- **S1 抽 `core/net/ip.dart`**：`_isIp` 在 `subscriptions_state`、`subscription_converter`、`latency_prober` 各写一份。抽共用 `isIp(host)` / `isIpv6(host)`，三处替换。
- **S2 拆 `ResultsTab` 子组件**：把 363 行的单 StatefulWidget 拆为 `ResultStatsRow`、`ResultTable`、`PushGithubButton` 三个无状态 widget，`ResultsTab` 只编排。
- **S3 拆 `convertSubscriptions`**：把 70 行巨函数拆为 `fetchRawNodes() / resolveHosts() / dedupeNodes()` 三步，主流程 3 行调度；便于测与扩展。

## 四、测试
- **T1 配套单测**：
  - `subscription_converter_test.dart`：B1 同 IP 不同端口都保留；P1/P2 注入 mock fetcher 断言并发与首源胜出。
  - `safe_fetch_test.dart`：B5 mock `DioExceptionType` → 分类标签。
  - `ip_test.dart`：S1 `isIp` IPv4/IPv6 与边界。
- **T2 Android 构建验证**：在能访问 Google Maven 的环境跑 `flutter build apk --release`，确认 AGP 9.0.1 可解析、`applicationDocumentsDirectory` 路径正确、Manifest 权限生效（本机当前受限）。
- **T3 `config_tab` 输入框回归测试**：widget 测试覆盖「打字时外值更新不重置光标」。

## 五、不改动项（YAGNI）
- `app_config.dart` 暂不引入 freezed/codegen；现状 366 行可控，补字段时手动同步 4 处即可。
- 网络安全配置 `network_security_config.xml` 暂不收紧；`usesCleartextTraffic="true"` 对本工具足够。

## 风险
- P1 并发上限取值需平衡「源数量」与「风控」：默认 32，可配置。过大可能被部分订阅器限流；过小失去并发收益。
- B6 主题开关加在 ConfigTab 顶部需注意布局顺序，避免破坏现有分区卡片观感。
