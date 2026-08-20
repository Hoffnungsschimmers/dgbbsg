# cfnb_app 项目会话上下文

> 本文档供其他 AI 接续本项目使用。最后更新：2026-07-21。

## 一、项目概况

**名称：** CF优选（cfnb_app）
**功能：** Cloudflare IP 优选工具——从订阅源抓取节点 → TCP 延迟测试 → 保留最优节点 → 推送 GitHub。
**技术栈：** Flutter 3.44.6 / Dart 3.12.2；`flutter_riverpod ^2.5.1`、`dio ^5.7.0`、`shared_preferences ^2.3.2`、`path_provider ^2.1.4`、`crypto`。
**构建命令：** `flutter build windows --release`（须先删 `build/windows` 强重建，否则 MSBuild 增量缓存导致 exe 时间戳不更新）。
**当前位置：** `D:\env\cfnb_app`。Flutter 在 `D:\env\flutter\bin`。运行命令前加：`$env:PATH="D:\env\flutter\bin;$env:PATH"`。

## 二、当前状态

- **分支：** `feat/subscription-latency-ux`
- **HEAD：** `15b173b`（基于 `main` 8723274）
- **`flutter analyze`：** 0 error，3 条历史 info（`github_push.dart` ×2、`config_tab.dart` ×1）
- **`flutter test`：** 70/70 通过
- **Windows 构建：** 成功（`build\windows\x64\runner\Release\cfnb_app.exe`）
- **Android APK 构建：** 无法在当前环境完成（无外网访问 `dl.google.com`，AGP 9.0.1 插件拉不到）。Manifest 权限已声明正确，需在能访问 Google Maven 的环境构建验证。
- **桌面快捷方式：** `C:\Users\2540\Desktop\CF优选.lnk` → 指向上述 exe。

## 三、架构总览

### 目录结构
```
lib/
├── app/
│   ├── app.dart              # AppShell 单页 + NavigationBar 三 Tab（配置/运行/结果）
│   ├── providers.dart        # Riverpod providers（configRepository/nodeParser/logger/subLogger/config/themeMode）
│   └── theme.dart            # AppTheme 主题定义
├── core/
│   ├── config/
│   │   ├── app_config.dart   # AppConfig 模型（全部字段/默认值/fromJson/toJson/copyWith/validate/resolveOutputPath）
│   │   └── config_repository.dart  # SharedPreferences 持久化 + 迁移逻辑
│   ├── fetch/
│   │   └── node_parser.dart  # 国家码映射（从 assets 加载）
│   ├── github/
│   │   └── github_push.dart  # GitHub API 推送优选结果文件
│   ├── latency/
│   │   ├── latency_filter.dart   # 延迟优选主流程（纯 TCP 延迟排序，已移除带宽测速）
│   │   └── latency_prober.dart   # TCP 延迟测量（measureLatency）+ latencyProbeAll 并发探测
│   ├── logging/
│   │   └── app_logger.dart   # 日志器（stream + snapshot + clearStream）
│   ├── net/
│   │   ├── ip.dart           # 共用 isIp/isIpv6/isIpv4（三处复用）
│   │   └── retry.dart        # 指数退避重试纯函数 retry<T>
│   └── subscription/
│       ├── generators_state.dart  # 订阅器状态（未详）
│       ├── sub_parser.dart        # 订阅链接解析（vless/vmess/trojan/ss/hysteria2/hy2/tuic）
│       └── subscription_converter.dart  # 订阅转换主逻辑（fetchSingle/fetchFirstWorking/convertSubscriptions/writeSubOutput）
├── features/
│   ├── results/
│   │   ├── result_state.dart  # ResultRow（node/latency）+ parseResultLines + ResultNotifier
│   │   └── results_tab.dart   # 结果 Tab（文件选择/统计/表格/推送 GitHub）
│   ├── subscriptions/
│   │   ├── config_tab.dart    # 配置 Tab（5 卡片：订阅输入/抓取/延迟优选/GitHub/外观）
│   │   ├── run_tab.dart       # 运行 Tab（订阅IP/延迟优选按钮 + LogView 日志）
│   │   └── subscriptions_state.dart  # 订阅/延迟运行逻辑（SubscriptionsNotifier/Dio/fetchHttpWithRetry/classifyFetchError）
│   └── widgets/
│       ├── common.dart        # 统一控件（card/AppButton/sectionTitle/LogView/RawTextView/labeledTextField/Switch/Slider/DoubleSlider/inputDecorationFor）
│       └── source_editor.dart # 数据源编辑器（未详）
└── main.dart                  # 入口（MaterialApp + themeModeProvider + AppShell）
```

### 关键设计决策
1. **单页 + 底部 Tab**：AppShell 用 `NavigationBar`（窄屏）/ `NavigationRail`（宽屏 ≥720px），三 Tab：配置/运行/结果。
2. **延迟测试 = 纯 TCP 建连**：`measureLatency` 做裸 Socket.connect，跑 N 次取最小延迟。带宽测速子系统已完全移除（`speed_prober.dart` 删除）。
3. **Dio 长生命周期**：`_dioSafe`/`_dioInsecure` 两个实例在构造期建好，复用 TCP keep-alive。`_dioInsecure` 跳过 TLS 证书校验。
4. **抓取重试**：`fetchHttpWithRetry` 用 `retry<T>` 纯函数做指数退避（初始 delay × 2^attempt，封顶 60s）。`_safeFetch` 传入 cfg 的超时/重试参数。
5. **路径解析**：配置存相对文件名（如 `addressesapi.txt`），运行时用 `resolveOutputPath(name, dir)` 拼接 `getApplicationDocumentsDirectory()` 绝对路径。
6. **输入框全选修复**：`_syncIf(ctl, v)` 差异守护（`if (ctl.text != v) ctl.text = v`），避免无条件重置破坏光标/全选。
7. **节点去重按 `ip:port#cc`**：同 IP 不同端口/国家码的合法变体保留，不再折叠。

## 四、AppConfig 字段一览

### 订阅转换
| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `subConvertEnabled` | bool | `true` | 启用订阅转换 |
| `subInputMode` | String | `'both'` | 输入模式：node/url/both |
| `subUrls` | List\<String\> | `[]` | 订阅链接列表 |
| `subNodeHost` | String | `'example.com'` | 节点域名 |
| `subNodeUuid` | String | `'xxxxxxxx-xxxx-...'` | 节点 UUID |
| `subGenerators` | List\<String\> | `defaultSubGenerators` | 订阅器列表（格式：名称\|域名） |
| `subDisabledGenerators` | Set\<String\> | `{}` | 已禁用的订阅器 |
| `subOutputFile` | String | `'addressesapi.txt'` | 订阅输出文件（相对名） |
| `subDefaultCountry` | String | `''` | 默认国家码 |
| `subResolveDomain` | bool | `true` | 是否解析域名 |

### 订阅抓取
| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `subFetchConnectTimeout` | int | `10` | 连接超时（秒） |
| `subFetchTimeout` | int | `20` | 总超时/读超时（秒） |
| `subFetchMaxRetries` | int | `2` | 重试次数（0=不重试，2=共 3 次尝试） |
| `subFetchRetryDelay` | double | `2.0` | 重试间隔（秒，指数退避 ×2） |
| `subInsecure` | bool | `false` | 跳过 TLS 证书校验 |

### 延迟优选
| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `subLatencyMaxMs` | int | `200` | 延迟上限（ms），超过丢弃 |
| `subLatencyTopN` | int | `50` | 保留前 N 名（0=全部） |
| `subLatencyOutputFile` | String | `'addressesapi_top.txt'` | 延迟优选输出文件 |
| `subLatencyTimeout` | double | `3.0` | TCP 探测超时（秒） |
| `subLatencyWorkers` | int | `50` | TCP 探测并发数 |
| `subLatencyProbes` | int | `3` | 每节点探测次数（取最小延迟） |
| `subLatencySni` | String | `'sdtbu.campusblog.ccwu.cc'` | SNI（未用，预留） |
| `subLatencyMinSuccessRate` | double | `0.34` | TCP 探测成功率下限（0-1） |

### GitHub 推送
| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `githubToken` | String | `''` | GitHub Token |
| `githubRepo` | String | `'Hoffnungsschimmers/cf-ip'` | 仓库 |
| `githubBranch` | String | `'main'` | 分支 |

### 外观
| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `guiTheme` | String | `'light'` | 主题（light/dark，UI 用 themeModeProvider） |

### 已删除的字段（不应再引用）
- `subSpeedEnabled`、`subSpeedLatencyLimit`、`subSpeedTimeout`、`subSpeedSizeMb`、`subSpeedWorkers`、`subSpeedProbes`、`subQualityLatencyWeight`、`subBandwidthRefMbps`（带宽测速子系统，已彻底移除）
- `subResolveWorkers`（从未实际接入，已彻底删除）

## 五、Git 提交历史（8723274..15b173b，共 26 个 feature commits）

```
15b173b refactor: 彻底删除未使用的 subResolveWorkers 字段
cc59bb7 feat: ConfigTab 重排分区+曝露订阅抓取参数（重试/间隔/超时/并发/insecure）
3de78b5 perf/fix: 接入 cfg 与指数退避重试到订阅抓取
c31477e feat: 抽 retry<T>, 调订阅抓取默认值为推荐配置
6c90dbe docs: 订阅抓取/延迟优选 UI 补全与重试 spec+plan
fd9b029 test: 适配 dedup 按 ip:port#cc 的语义（两 host 同 IP 仍保留两条）
8b7a63c Revert "perf: 订阅源有限并发抓取 + race-first 回退 + DNS 限流"
91bd9de feat: ConfigTab 恢复深色主题切换开关
42974eb fix: 滑块/路径边界 + 延迟日志节流
61b2bfe refactor: ResultsTab 用 ref.listen + 拆子组件
5498ace perf/fix: Dio 连接复用 + 抓取异常分类
29030d0 perf: 订阅源有限并发抓取 + race-first 回退 + DNS 限流 [已 revert]
4d7d23a fix: 节点去重按 ip:port#cc，抽取共用 isIp
e86391b docs: cfnb_app 全面优化 spec + plan
b258248 fix: 结果Tab候选文件按文档目录绝对路径判断存在性(修复运行后结果不显示)
ae3ae52 fix: 移除 app.dart 未使用的 theme.dart 导入
22fd42e feat: Android 清单声明 INTERNET 与明文流量
ed6a2ef refactor: AppShell 改为单页底部Tab(配置/运行/结果)
f365517 refactor: 拆分运行Tab与结果Tab，去掉独立页壳
6eb4bf9 fix: 移除对已删 settings_fields 的测试导入
6590105 refactor: 合并设置到配置Tab，删除 settings 页与重复 helper
81e916e feat: 输出文件路径解析到文档目录（Android 适配）
00ac8ff fix: 结果表移除已无数据的带宽/质量分列
577418b refactor: 统一配置控件 helper 到 common.dart
73e8860 docs: 订阅器页合并+Android适配 实施计划
35ee9e3 docs: 订阅器页合并+Android适配 设计文档
```

## 六、核心函数签名参考

```dart
// lib/core/net/retry.dart
Future<T> retry<T>(Future<T> Function() body, {
  required int maxRetries,
  required Duration initialDelay,
  Future<void> Function(Duration)? sleep,  // 测试注入用
})

// lib/core/net/ip.dart
bool isIp(String host)
bool isIpv4(String host)
bool isIpv6(String host)

// lib/core/config/app_config.dart
String resolveOutputPath(String name, String baseDir)

// lib/features/subscriptions/subscriptions_state.dart
String classifyFetchError(Object e, String url)

Future<String> fetchHttpWithRetry({
  required dio_pkg.Dio dio,
  required String url,
  required int connectTimeoutSec,
  required int sendTimeoutSec,
  required int receiveTimeoutSec,
  required int maxRetries,
  required int retryDelayMs,
  Future<void> Function(Duration)? sleep,
})

// lib/core/latency/latency_prober.dart
Future<(double?, int)> measureLatency(String ip, int port, Duration timeout, {String? sni, int probes = 1})

Future<(List<LatencyResult>, int tested, int connected)> latencyProbeAll(
  List<String> nodes, {
  required Duration timeout,
  required int workers,
  int probes = 1,
  double minSuccessRate = 1.0,
  Map<String, String>? nodeSource,
  String? sni,
  Future<(double?, int)> Function(String ip, int port, Duration timeout, {int probes, String? sni})? probe,
  void Function(String)? onLog,
})

// lib/core/latency/latency_filter.dart
static Future<(List<String>, int, int)> run({
  required List<String> nodes,
  required String outputFile,
  required int latencyMaxMs,
  required Duration timeout,
  required int workers,
  int probes = 1,
  double minSuccessRate = 1.0,
  int topN = 200,
  Map<String, String>? nodeSource,
  String? sni,
  Future<(double?, int)> Function(...)? probe,
  void Function(String)? onLog,
})
```

## 七、已知遗留 / 待做

### Minor（非阻塞）
- `labeledDoubleSlider` 的 `divisions` 在 min==max 时为 0（`common.dart`），当前无调用触发。
- `flushTimer` 末次可补 `cancel()`（`latency_prober.dart` 日志节流），无实际影响。
- `isIpv4` 对十六进制前缀（如 `0x0.0x0.0x0.0x0`）有 false-positive（低概率）。
- `fetchFirstWorking` 的 race-first 孤儿 future 不会被取消（被忽略，`try/on Object` 兜底）。
- `app_config.dart` 未使用 `material.dart` import 可清理（当前 analyze 不报错）。

### 待验证
- **Android APK 构建**：当前环境无外网（AGP 9.0.1 拉不到），需在能访问 Google Maven 的环境（CI/代理）构建 `flutter build apk --release` 验证。
- **Android 真机**：验证 `getApplicationDocumentsDirectory()` 路径、`INTERNET` 权限、`usesCleartextTraffic` 明文流量。

### 订阅抓取行为说明
- 当前抓取是**串行的**（`convertSubscriptions` 内 `for` 循环逐源处理）。曾尝试并发版本（commit `29030d0`），用户觉得"太快"已 revert（`8b7a63c`）。若需重新启用并发，参考 docs 里的 spec/plan。
- `fetchFirstWorking` 当前也是 `Future.wait`（等所有候选 URL 完成才挑能解析的）。曾尝试 race-first 版本，一并 revert。恢复并发时可同步恢复 race-first。

## 八、测试说明

- 全量：`flutter test`（当前 70 个测试）
- 关键测试文件：
  - `test/core/config/app_config_test.dart`（AppConfig 默认值/fromJson/toJson/copyWith）
  - `test/core/net/retry_test.dart`（retry 纯函数 4 个用例）
  - `test/core/net/ip_test.dart`（isIp 2 个用例）
  - `test/features/results/result_state_test.dart`（parseResultLines 2 个用例）
  - `test/features/subscriptions/safe_fetch_test.dart`（fetchHttpWithRetry + classifyFetchError + 重试逻辑）
  - `test/features/settings_results_test.dart`（parseResultLines 兼容性）
  - `test/core/subscription/` 目录下还有订阅解析/转换相关测试

## 九、文档

- `docs/superpowers/specs/` 目录下有多个设计文档（spec）：
  - `2026-07-19-subscription-and-latency-design.md`（原始延迟测试设计）
  - `2026-07-19-ui-merge-android-design.md`（UI 合并 + Android 适配设计）
  - `2026-07-19-app-optimization-design.md`（全面优化设计）
  - `2026-07-21-fetch-retry-config-design.md`（订阅抓取重试/配置补全设计）
- `docs/superpowers/plans/` 目录下有对应的实施计划（plan）。
- `docs/superpowers/` 下还有早期的 `cfnb-defect-fixes` spec/plan（历史参考）。
