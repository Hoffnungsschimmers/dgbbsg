# CFNB App — 优选流程缺陷全面修复 设计文档

日期：2026-07-18
范围：保留「订阅IP → 延迟优选 → 手动推送 GitHub」三步流程，删除整套旧「优选运行」流水线后的遗留缺陷清理。

## 1. 目标与原则

- 在不改变产品形态（三步流程）的前提下，修复静态审查发现的全部缺陷，并清理死代码。
- 用户已确认的三项关键决策：
  - **A2 延迟测法保持裸 TCP RTT**（不接入 `measureTlsLatency`）。
  - **A3 默认 `subNodeUuid` 改为合法 v4 形态占位**（`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`，y∈{8,9,a,b}），以触发标准 edgetunnel `BEST_SUB` 公开优选分支，无需用户填真实 uuid。
  - **C15 死字段彻底删除**：从 AppConfig、settings UI 分组、config 迁移逻辑、测试中移除全部无活代码路径的字段；SharedPreferences 旧键读时忽略（向后兼容）。
- 推送策略变更（用户明确）：**GitHub 推送只推送后缀为 `.top` 的文件**（即 `subLatencyOutputFile`，默认 `addressesapi_top.txt`），其他文件一律不推送。

## 2. 缺陷修复清单

### 2.1 致命 / 高优先级

| ID | 文件 | 问题 | 修复 |
|----|------|------|------|
| A1 | `result_state.dart` | `ResultRow.country` 取 `node.split('#').last`，`US@CM` 会把来源拼进国家列 | 改用 `nodeCountry()`（按 `#` 取后、按 `@` 取前），与 `latency_filter` 同源 |
| A4 | `github_push.dart` + `subscriptions_state.dart` | 两个 Dio 实例、手工 header copy（已修 401 但仍是抽象泄漏）；`onHttpClientCreate` 已 deprecate | 收敛为**单一直连 Dio**：在 `subscriptions_state` 复用 `GithubPush` 的直连 Dio（或抽到共享模块）；`_httpFetch` 走该 Dio，去掉手工 headers；用 `createHttpClient` 替代 `onHttpClientCreate` |
| A5 | `app_config.dart`/`results_page.dart`/`providers.dart` | `outputFile='ip.txt'` 与产品脱节，结果页还列它、刷新按钮刷它 | 从 AppConfig 删 `outputFile`/`logFile`；结果页候选文件只留 `subOutputFile`+`subLatencyOutputFile`；刷新按钮改刷 `subLatencyOutputFile` |
| B6 | `latency_filter.dart` | 保留「延迟 ≤ max」无数量上限，低延迟节点会无限堆积 | 新增 `maxKeep` 参数（默认 200）；`withinMax` 排序后 `take(maxKeep)` |
| B7 | `subscriptions_state.dart` | `probes:3` 硬编码 | 新增 `subLatencyProbes` 字段（默认 3），`runLatency` 透传；`minSuccessRate` 保持 1.0 |
| B8 | `subscription_converter.dart` | `fetchFirstWorking` 串行尝试候选 URL | 改 `Future.wait` 并发，取首个解析出节点的结果（保留兜底非空） |
| B9 | `subscription_converter.dart` | 单 URL 失败无逐 URL 日志 | `fetchSingle` 失败时记录 url+错误；`convertSubscriptions` 在 generator 级已记录，补充 per-URL 明细 |
| B10 | `results_page.dart` | 结果页不展示最高质量分 Q | 解析行尾 `Qxx.xx`，新增 `_bestQuality()`，加「最高质量分」统计卡 |

### 2.2 中优先级

| ID | 文件 | 问题 | 修复 |
|----|------|------|------|
| B11/B12 | `subscriptions_state.dart` + `results_page.dart` | 推送逻辑可推任意文件 | `pushFile` 入口强制 `file.toLowerCase().endsWith('.top')` 校验，否则返回 `(false,0,'仅支持推送 .top 后缀文件')`；结果页去掉文件下拉选择，「推送 GitHub」按钮固定推 `cfg.subLatencyOutputFile`；文案改为「推送 GitHub」 |
| B13 | `app_config.dart` | `subConvertEnabled` 默认 false，新手点「订阅IP」无反应 | 默认改 `true` |
| B14 | `app_config.dart`/`latency_prober.dart` | `subDefaultCountry='UN'` 触发 `extractCountryCode` 失败写错误 `UN` | 默认改 `''`（空串→不写 `#`）；`nodeCountry` 对空源返回 `''`；写节点时 `cc` 为空则不拼后缀 |

### 2.3 工程债（C15 删干净）

删除以下 AppConfig 字段及其 `fromJson`/`toJson`/`copyWith`/校验/`settings_fields` 分组/迁移逻辑：
- CF DNS 系列：`cfEnabled/cfApiToken/cfZoneId/cfDnsRecordName/cfTtl/cfProxied/cfDnsConnectTimeout/cfDnsReadTimeout/dnsRecordType`
- WxPusher：`enableWxpusher/wxpusherAppToken/wxpusherUids/wxpusherApiUrl/notifyTimeout/notifyConnectTimeout`
- ASN：`asnSourcesEnabled/asnSources/asnSourcesIpv6/asnSourcePort/asnSourceCountry/asnSourceMaxIps/asnSourceTimeout/asnSourceConnectTimeout/asnSourceRetryMax/asnSourceRetryDelay`
- 可用性：`testAvailability/availabilityCheckApi/availabilityTimeout/availabilityConnectTimeout/availabilityRetryMax/availabilityRetryDelay/availabilityWorkers`
- 广告：`adHeaderEnabled/adHeaderLines/adFooterEnabled/adFooterLines/adPerlineEnabled/adPerlineText`
- 旧筛选/数量：`useGlobalMode/globalTopN/perCountryTopN/perCountryQuota/bandwidthCandidates/dnsUpdateTargetCount/qualitySpeedWeight/qualityLatencyWeight`
- 预过滤/DNS 过滤：`preFilterPortEnabled/preFilterPorts/preFilterBlockedEnabled/preFilterBlockedCountries/filterCountriesEnabled/allowedCountries/filterBlockedCountriesEnabled/blockedCountries/dnsIpRiskFilterEnabled/dnsIpRiskMaxLevel/filterIpv6Availability`
- 旧 TCP/超时：`tcpProbes/timeout/socketDefaultTimeout/progressPrintInterval/maxWorkers/fallbackWorkers`
- 自动调度：`autoScheduleEnabled/autoScheduleIntervalHours`
- 旧带宽测速组：`bandwidthSizeMb/bandwidthTimeout/bandwidthRetryMax/bandwidthRetryDelay/bandwidthUrlTemplate/bandwidthProcessBuffer/bandwidthConnectTimeout/bandwidthWorkers`
- GitHub 同步重试：`githubSyncMaxRetries/githubSyncRetryDelay/gitSyncProcessTimeout/dnsUpdateMaxRetries/dnsUpdateRetryDelay`
- ip.txt 控制：`ipTxtShowBandwidth/ipTxtShowLatency`
- 输出：`outputFile/logFile`
- fetch 重试（保留 `subFetch*`）：`fetchMaxRetries/fetchRetryDelay/fetchTimeout/fetchConnectTimeout/enableLogging`

保留活字段：
`subConvertEnabled/subInputMode/subUrls/subNodeHost/subNodeUuid/subGenerators/subDisabledGenerators/subOutputFile/subDefaultCountry/subResolveDomain/subFetchTimeout/subFetchConnectTimeout/subFetchMaxRetries/subFetchRetryDelay/subResolveWorkers/subLatencyMaxMs/subLatencyOutputFile/subLatencyTimeout/subLatencyWorkers/subLatencyProbes(新)/subLatencySni/subSpeedEnabled/subSpeedLatencyLimit/subSpeedTimeout/subSpeedSizeMb/subSpeedWorkers/subQualityLatencyWeight/githubToken/githubRepo/githubBranch/guiTheme/additionalSources/subGenerators`

`settings_fields.dart` 同步删除对应分组（1/2/3/4/5/8/9/10 大部分），仅保留：订阅转换、延迟优选、带宽测速、GitHub 推送、外观(主题)。

`config_repository.dart` 迁移精简：
- 保留 `additionalSources`/`subGenerators` 补全（空时补默认）
- 保留 `subSpeed*` 升级（size 1→10、timeout 15→20、workers 20→10）
- 保留 `subLatencyMaxMs==0→200`、`subSpeedLatencyLimit==0→200`
- 删除 `SUB_LATENCY_TOPN` 旧迁移（已无意义）
- 新增 `subLatencyProbes` 默认 3、`subDefaultCountry` 默认 `''`（旧 'UN' 视为未配置→改 `''`）

### 2.4 其他

- C16 `defaultAdditionalSources` 中硬编码 `D:\env\cfnb\cfdata_ips.txt` 移除（本地绝对路径，跨机无效）。
- 修复 `flutter analyze` 现有 23 个 issue：unused imports、curly braces、await_only_futures（results_page 刷新）、deprecated `onHttpClientCreate`、`unnecessary_import`、`unused_element`（settings_page 的 `_slider/_doubleSlider/_textList`）、speed_prober `dart:typed_data` unused import、tests 的 unused 警告。

## 3. 数据流向（修复后）

```
订阅器/订阅链接 ──convertSubscriptions──> addressesapi.txt (+ _src.json)
                                          │ (subOutputFile)
                                          ▼
                                   LatencyFilter.run
                                   (裸 TCP 延迟, probes=subLatencyProbes,
                                    保留 ≤ subLatencyMaxMs, 上限 maxKeep,
                                    带宽测速 → 质量分 Q 排序)
                                          │
                                          ▼
                                  addressesapi_top.txt (+ .json)
                                          │ (subLatencyOutputFile, .top 后缀)
                                          ▼
                              手动「推送 GitHub」→ 仅推 .top 文件
```

## 4. 测试策略

- 现有测试保留并通过：`app_config_test` / `latency_test` / `subscription_converter_test` / `github_push_test` / `settings_results_test` / `node_parser_test` / `sub_parser_test`。
- 更新 `app_config_test` 中对已删字段的断言；新增：
  - `pushFile` 拒绝非 `.top` 文件（用注入 sender 的 `GithubPush` 验证不发起请求）。
  - `nodeCountry('1.2.3.4:443#US@CM')` 返回 `'US'`；空源返回 `''`。
  - `LatencyFilter.run` 带 `maxKeep` 截断验证。
  - `fetchFirstWorking` 并发返回首个可用。
- 最终 `flutter analyze` 0 issue，`flutter test` 全绿。

## 5. 验收标准

1. `flutter analyze` 无 error/warning（仅允许 info 级）。
2. `flutter test` 全部通过。
3. 结果页「国家」列对 `US@CM` 显示 `US`；最高质量分卡片显示正确 Q 值。
4. 点击「推送 GitHub」仅推送 `addressesapi_top.txt`；若文件非 `.top`，返回明确失败提示且不发请求。
5. 配置面板只显示订阅/延迟/带宽/GitHub/主题；SharedPreferences 旧键读时不报错。
6. 「订阅IP」默认启用（`subConvertEnabled=true`）。
