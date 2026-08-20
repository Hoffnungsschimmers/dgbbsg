# CF优选 订阅抓取优化 + 延迟测试改进 + 输入框 UX 修复 设计

**日期**: 2026-07-19
**状态**: 设计已确认,待用户复审

## 背景

CF优选工具(D:\env\cfnb_app)目前存在三类问题:

1. **输入框 UX bug**:订阅器页/设置页的 TextField 在用户输入一个字符后会自动全选,导致下一次按键覆盖已有内容。
2. **订阅抓取痛点**:
   - 死源(如天诚 cm.soso.edu.kg 的证书 Hostname mismatch)按 `maxRetries=3` 重试,每次白等 3s,源串行执行   - 源之间串行执行(`for` 循环逐源),总耗时 = Σ单源耗时
   - `Dio` 的 `validateStatus` 默认严格,4xx 响应 body 即便含节点也被丢弃
   - 证书不匹配的源无开关可控
3. **延迟测试策略**:用户确认用裸 TCP 建连;但当前探针策略(默认 probes=3 但 `minSuccessRate=1.0`)对网络抖动不友好,网络抖动一次漏掉真活节点。

## 目标

- 修复输入框全选 UX bug
- 现有源调透抓取策略,提升抓取成功率 + 降低总耗时
- 裸 TCP 延迟测试策略:容忍网络抖动,1 次成功即记活,取最小延迟
- 默认行为安全,新功能以开关方式提供

## 非目标

- 不增加新数据源/新订阅器(用户明确选择「现有源调透策略」)
- 不实现真代理隧道 urltest(开发量过大,暂缓)
- 不加 HTTP 应用层 RTT 探测(用户环境曾有阻拦,已试过回退)

## 设计

### 1. 输入框全选 bug 修复

**根因**: `_syncControllers` 在 `build` 每次重建时无条件调用 `_xxxCtl.text = cfg.xxx`。
Flutter 的 `TextField` 在 `controller.text` 被外部赋值时(即使值相同),会重置 selection 为全选。
用户输入一个字符 → `onChanged` 触发 `_save` → `configProvider` 失效重建 → `build` 重跑 →
`_syncControllers` 无条件赋值 → 全选。

**现有正确模式**: `_syncList` 已有差异守护 `if (ctl[i].text != values[i]) ctl[i].text = values[i]`

**修复**: 统一引入差异守护 helper:

```dart
void _syncIf(TextEditingController ctl, String v) {
  if (ctl.text != v) ctl.text = v;
}
```

替换 `subscriptions_page.dart` / `settings_page.dart` 中所有 `_xxxCtl.text = cfg.xxx` 模式
为 `_syncIf(_xxxCtl, cfg.xxx)`。

**影响**:
- `subscriptions_page.dart` 行 52-58、96(8 处)
- `settings_page.dart` 的 `sync(key, value)` 闭包(已用差异守护,但确认逻辑对)

### 2. 全局「跳过 TLS 证书校验」开关

**新增 config 字段**:
- `subInsecure` (bool, 默认 `false` — 安全默认)

**实现**:
- `app_config.dart`: 加字段 + fromJson/toJson/copyWith
- `subscriptions_state._httpFetch`: 根据 `cfg.subInsecure` 动态设置 `IOHttpClientAdapter`
  的 `onHttpClientCreate` 回调:
  ```dart
  if (cfg.subInsecure) {
    _dio.httpClientAdapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (_, __, ___) => true;
        return client;
      };
  }
  ```
  关闭时不设 adapter,维持默认严格校验。
- **全局开关**: 开了所有源都跳过,不开所有源都严格。不细化到单源(避免 UI 复杂度)。
- **UI**: 订阅器页「高级参数」加 Switch「跳过 TLS 证书校验(不安全)」,默认关。
  开关旁标注警告文字。

**安全考量**:
- 默认关闭 — 用户不主动开就维持严格校验,等价于当前行为
- 开启后能抓证书不匹配的源(如天诚),但暴露于 MITM 风险 — 用户自担风险
- UI 警告标注 +(可选)启用时记录一次 logger 警告

### 3. 订阅抓取策略优化

#### 3a. 源间并发(降总耗时)

**现状**: `subscription_converter.dart` 行 ~197 的 `for (final (name, urls) in tasks)` 串行执行。
10 个源 × 单源最坏 ~60s = ~10 分钟。

**改造**:
```dart
await Future.wait(tasks.map((task) async {
  final (name, urls) = task;
  // 单源内仍走 fetchFirstWorking(三 URL 并发取首个能解析节点的)
  final bodies = name == 'url'
      ? await Future.wait(urls.map((u) => fetchSingle(u, fetch, maxRetries: ..., retryDelay: ...)))
      : [await fetchFirstWorking(urls, fetch, maxRetries: ..., retryDelay: ...)];
  // 收集节点(单 isolate 事件循环天然串行,无需锁)
  final got = _parseBodies(bodies, ...);
  // 加锁保护 rawNodes/state push(虽单 isolate,但 Future 内 await 间隔可能交错,用同步区段即可)
  rawNodes.addAll(got);
  onLog?.call('[+] ...');
}));
```

**总耗时**: 降到 `max 单源`,实测 ≤ 25s。

**注意**:
- 节点解析(`SubParser.parseSubscriptionLinks`)是纯 CPU,无并发问题
- `rawNodes.addAll(got)` 在 await 完成后执行,单 isolate 串行,无锁

#### 3b. URL 失败分类 + 证书错短路

**现状**: `_safeFetch` 抛 `Exception`, `fetchSingle` 无差别重试。
证书错重试 3 次还是证书错,白白等 9-15s。

**异常分类判断逻辑** (4xx body 处理明确):
- HTTP 响应 4xx (`validateStatus` 放宽后 dio 不抛) → `body` 非空且 SubParser 从中能解析出节点 → 当正常结果返回;
- 4xx body 空 / 无节点 → 抛 `TransientFetchException`(可重试)
- 抓 `HandshakeException` / 错误消息含 `CERTIFICATE` / `Handshake error` → 抛 `CertFetchException`
- 5xx / 超时 / 连接拒绝 → 抛 `TransientFetchException`

**改造**: 抽象 `FetchException` 体系:

```dart
class FetchException implements Exception {
  final String message;
  final String url;
  FetchException(this.url, this.message);
  @override String toString() => '[$url] $message';
}

class CertFetchException extends FetchException {
  CertFetchException(super.url, super.message);
}

class TransientFetchException extends FetchException {
  TransientFetchException(super.url, super.message);
}
```

`_safeFetch` 异常分类:
- 捕获 Dio 异常后:
  - 错误消息含 `CERTIFICATE` / `Handshake` → 抛 `CertFetchException`
  - 其他 → 4xx 走「body 有节点则成功」分支,5xx/超时 → 抛 `TransientFetchException`

`fetchSingle` 重试策略:
```dart
for (var attempt = 0; attempt <= maxRetries; attempt++) {
  try {
    return await fetch(real);
  } on CertFetchException {
    // 证书错重试无意义 → 立即放弃
    rethrow;
  } on TransientFetchException catch (e) {
    lastErr = e.message;
    if (attempt < maxRetries) {
      await Future.delayed(Duration(seconds: retryDelay));
    }
  }
}
throw TransientFetchException(real, lastErr);
```

**效果**: 证书错源立即失败(0s),5xx/超时源按配置重试(可恢复)。

#### 3c. Dio `validateStatus` 放宽

**现状**: `validateStatus` 默认 `(s) => s < 200 || s >= 300` → 4xx 抛异常,body 丢失。

**改造**: `_httpFetch` 加 `validateStatus: (s) => s < 500`:
- 5xx 仍抛(`DioException`)
- 4xx 不抛,返回 resp,`_safeFetch` 拿 body 让 `SubParser` 判断
- **仅对订阅抓取生效**: `_httpFetch` 是订阅专用,`github_push.dart` 的 Dio 不动

### 4. 延迟测试策略(裸 TCP + 容忍)

#### 4a. 探针策略

**确定方案**:
- 默认 `subLatencyProbes = 3`
- `measureTcpLatency` 语义: **跑完 N 次,取最小成功延迟;失败累积到必然不可能成功时提前放弃**

```dart
Future<(double?, int)> measureTcpLatency(
  String ip, int port, Duration timeout, {
  int probes = 1, String? sni,
}) async {
  double? minLatency;
  var success = 0;
  for (var i = 0; i < probes; i++) {
    final sw = Stopwatch()..start();
    Socket? raw;
    try {
      raw = await Socket.connect(ip, port, timeout: timeout);
      final lat = sw.elapsedMilliseconds.toDouble();
      if (minLatency == null || lat < minLatency) minLatency = lat;
      success++;
    } on SocketException {
      // 本次失败,继续后续探针
    } on TimeoutException {
      // 本次超时,继续后续探针
    } catch (_) {
      // 其他异常,继续后续探针
    } finally {
      try { raw?.destroy(); } catch (_) {}
    }
  }
  return (minLatency, success);
}
```

**含义**: 跑完 N 次探针,任一次成功即记 `success`,取**最小**成功延迟。N=3 时 1 次成功 2 次失败仍记活(`success>=1`),3 次全失败返回 `(null, 0)`。`minSuccessRate` 在 `LatencyFilter` 层判断(默认 0.34,即 `1/3`)。

**不早退**: 取最小需要所有探针结果,跑完 N 次是必要的;单节点最坏用时 `N × timeout`(N=3、timeout=3s → 9s),已可接受。

#### 4b. `minSuccessRate` 配置化(放宽默认)

**现状**: `LatencyFilter.run` 默认 `minSuccessRate = 1.0`(N 次全成功才算活)

**改造**:
- 加 config 字段 `subLatencyMinSuccessRate` (double, 默认 `0.34` ≈ 1/3)
- `runLatency` 调 `LatencyFilter.run` 时传入 `cfg.subLatencyMinSuccessRate`
- `LatencyFilter.run` 内 `rate = ok / probes`, `okLat = lat != null && rate >= minSuccessRate`
- UI 加 slider 0.0~1.0,步长 0.05,默认 0.34

**效果**:
- 默认 0.34:3 次探针 1 次成功就保留(容忍网络抖动)
- 调到 1.0:严格模式(适合追求稳定结果的用户)
- 调到 0.1:宽松模式(几乎 TCP 能连一次就保留,牺牲精度换召回)

#### 4c. 实时日志改进(顺手)

**现状**: 按遍历顺序打印 `[i/N] ip:port 160ms`,高延迟/超时刷屏。

**改造**:
- **不动**实时明细日志(用户可看进度)
- **末尾追加**一条 Top 10 汇总(延迟升序前 10 + 来源):
  ```
  === 延迟优选完成: 测试 456 / 连通 380 / 保留 50 ===
  Top 10 最快:
  1. 47.76.218.163:443  50ms  @S5公益
  2. 43.161.254.188:10086  52ms  @洛璃  (示例)
  ...
  ```

`LatencyFilter.run` 末尾展开:
```dart
if (onLog != null) {
  onLog('=== 延迟优选完成: 测试 $tested / 连通 $connected / 保留 ${keptResults.length} ===');
  for (var i = 0; i < keptResults.length && i < 10; i++) {
    final r = keptResults[i];
    final src = nodeSource?[r.node] ?? '';
    onLog('${i + 1}. ${r.node}  ${r.latencyMs!.toStringAsFixed(0)}ms${src.isNotEmpty ? "  @$src" : ""}');
  }
}
```

### 5. 架构边界(单职责)

| 文件 | 职责 | 边界 |
|------|------|------|
| `subscription_converter.dart` | 抓取编排(源任务、并发、URL 候选、重试分类) | 不关心 HTTP 怎么发 |
| `subscriptions_state.dart` | HTTP 注入(Dio 配置、证书策略、超时、validateStatus) | 通过 `SubFetcher` 注入 |
| `latency_prober.dart` | 纯单节点 TCP 探测(超时、探针、容忍) | 不关心编排/写入 |
| `latency_filter.dart` | 编排(并发池、排序、写文件、汇总日志) | `probe` 注入 |
| `app_config.dart` | 数据模型,无逻辑 | - |

### 6. 测试

| 测试文件 | 验证 |
|----------|------|
| `test/subscription/fetch_retry_test.dart` | `fetchSingle` 在 `CertFetchException` 时立即放弃(不重试);在 `TransientFetchException` 时按 `maxRetries` 重试;全部失败抛 |
| `test/subscription/fetch_first_working_test.dart` | 三 URL 并发,首个能解析节点即赢;都无节点返回兜底;空 urls 返回 '' |
| `test/subscription/convert_concurrent_test.dart` | `convertSubscriptions` 源间并发 mock 抓取耗时,断言总耗时 ≈ max 而非 sum |
| `test/latency/measure_tcp_test.dart` | N=3:1 次成功 2 次失败仍记活(lat != null, ok >= 1);取最小;3 次全失败返回 null |
| `test/latency/min_success_rate_test.dart` | rate filtering:`1/3 成功` 在 0.34 阈值过、在 1.0 阈值不过 |
| `test/ux/sync_if_test.dart` | `_syncIf` 值相同时不调用 controller.text setter(用 mock 计数);值不同时调用 |

## 影响文件清单

| 文件 | 改动类型 |
|------|----------|
| `lib/core/config/app_config.dart` | +`subInsecure` +`subLatencyMinSuccessRate` |
| `lib/core/config/config_repository.dart` | 迁移补默认 |
| `lib/core/subscription/subscription_converter.dart` | `convertSubscriptions` 源间并发;`fetchSingle` 异常分类重试;`FetchException` 体系 |
| `lib/features/subscriptions/subscriptions_state.dart` | `_httpFetch` 动态证书策略 + validateStatus 放宽;`_safeFetch` 分类抛异常 |
| `lib/core/latency/latency_prober.dart` | `measureTcpLatency` 早期失败放弃 |
| `lib/core/latency/latency_filter.dart` | `minSuccessRate` 默认接 config;末尾汇总日志 |
| `lib/features/subscriptions/subscriptions_page.dart` | `_syncIf` 替换无条件赋值;+`subInsecure` 开关;+`subLatencyMinSuccessRate` slider |
| `lib/features/settings/settings_page.dart` | `sync` 差异守护检查 |
| `test/subscription/fetch_retry_test.dart` | 新增 |
| `test/subscription/fetch_first_working_test.dart` | 新增 |
| `test/subscription/convert_concurrent_test.dart` | 新增 |
| `test/latency/measure_tcp_test.dart` | 新增 |
| `test/latency/min_success_rate_test.dart` | 新增 |
| `test/ux/sync_if_test.dart` | 新增 |

**代码量估算**: 约 350 行实现 + 200 行测试。

## 风险与权衡

| 风险 | 缓解 |
|------|------|
| 源间并发后日志顺序乱 | 每 source task 在 await 完成后再打 `[+]` 汇总日志,顺序按完成时序 |
| `subInsecure` 默认关可能用户不知道开关 | UI 警告文字 + 启用时 logger.warning |
| `minSuccessRate` 默认 0.34 可能偏宽松 | UI slider 让用户调;默认 0.34 而非 0.0 平衡抖动容忍 |
| `validateStatus` 放宽后 4xx body 可能是 HTML | `SubParser` 解析失败自动跳过(body 找不到节点)|
| Dio `httpClientAdapter` 动态切在并发下竞争 | **不用共享 `_dio`**: `_safeFetch` 每次调用前用工厂 `_makeDio(insecure: cfg.subInsecure)` 新建 Dio。Dio 创建成本低,且彻底避免并发竞争。新建 Dio 与原共享 `_dio` 配置一致(超时、UA、validateStatus) |

## 验证

- `flutter analyze` 0 issue
- `flutter test` 全部通过(51 现有 + 6 新增 = 57)
- `flutter build windows --release` 成功(注意:每次需删 `build/windows` 强制重建,避免增量缓存 bug)
- 实测:订阅 IP 转换 + 延迟优选,456 节点延迟测试 0 个全超时,Top 50 延迟在合理区间
