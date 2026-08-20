## CFData-WEB 功能整合方案

### 核心思路
在现有 5 个 Tab 基础上，新增第 6 个 Tab「IP扫描」，包含 CFData-WEB 的三大核心功能：**官方 CF IP 段扫描**、**HTTPing (TTFB) 模式**、**速度测试**。不修改现有功能，纯粹做增量。

### 新增文件清单

| 文件 | 用途 |
|------|------|
| `lib/core/scanner/cf_range_scanner.dart` | CF CIDR IP 段生成器 |
| `lib/core/scanner/http_ping.dart` | HTTPing (TTFB) 探测函数 |
| `lib/core/scanner/speed_test.dart` | 下载速度测试 |
| `lib/core/scanner/scanner_state.dart` | 扫描状态管理 (Riverpod StateNotifier) |
| `lib/features/scanner/scanner_tab.dart` | 扫描页 UI |
| `lib/features/scanner/scanner_config_panel.dart` | 扫描参数配置面板 |
| `lib/features/scanner/scanner_results_panel.dart` | 扫描结果展示面板 |
| `test/core/scanner/cf_range_scanner_test.dart` | CF 范围扫描测试 |
| `test/core/scanner/http_ping_test.dart` | HTTPing 测试 |
| `test/core/scanner/speed_test_test.dart` | 速度测试测试 |

### 修改文件清单

| 文件 | 改动 |
|------|------|
| `lib/app/app.dart` | 添加第 6 个 Tab「IP扫描」，mod 5→6 |
| `lib/app/shortcuts.dart` | 添加 Ctrl+6 快捷键 |
| `lib/core/net/ip.dart` | 扩展 `isCloudflareIp()` 补充更多 CF CIDR 段 |

### 详细设计

#### 1. CF CIDR 范围扫描器 (`cf_range_scanner.dart`)

```dart
/// 从 Cloudflare 已知 CIDR 段中随机采样 IP 列表。
/// 支持 IPv4 和 IPv6，按数据中心分组。
class CfRangeScanner {
  /// CF IPv4 CIDR 段列表
  static const ipv4Ranges = [
    '104.16.0.0/12',
    '162.158.0.0/15',
    '172.64.0.0/13',
    '108.162.192.0/18',
    '13.32.0.0/13',
    '13.224.0.0/13',
    '13.249.0.0/16',
    // 补充更多 CF 段
    '104.24.0.0/14',
    '172.67.0.0/16',
    '141.101.0.0/16',
    '103.21.244.0/22',
    '103.22.200.0/22',
    '103.31.4.0/22',
    '188.114.96.0/20',
    '190.93.240.0/20',
    '197.234.240.0/22',
    '198.41.128.0/17',
  ];

  /// 从 CIDR 段中随机采样 N 个 IP
  static List<String> sampleIPv4({int count = 1000}) { ... }

  /// 生成 CIDR 段中所有 IP（用于小段扫描）
  static List<String> expandCIDR(String cidr) { ... }
}
```

#### 2. HTTPing 探测器 (`http_ping.dart`)

```dart
/// HTTP TTFB (Time To First Byte) 探测。
/// 与 measureLatency 相同的签名，可直接传入 latencyProbeAll 的 probe 参数。
Future<(double?, double?, int)> measureHttpTtfb(
  String ip, int port, Duration timeout, {int probes = 1}
) async {
  // 对每个 probe：
  //   1. 构造 HTTP GET 请求到 http://<ip>:<port>/cdn-cgi/trace
  //   2. 设置 Host: www.cloudflare.com
  //   3. 用 Stopwatch 计时到收到第一个字节
  //   4. 返回 (minTtfb, jitter, successCount)
}
```

关键：签名与 `measureLatency` 完全一致（`Future<(double?, double?, int)> Function(String, int, Duration, {int probes})`），可直接传入现有 `latencyProbeAll` 的 `probe` 参数，复用全部并发控制、进度回调、取消机制。

#### 3. 速度测试器 (`speed_test.dart`)

```dart
/// 下载速度测试：从指定 URL 下载数据，测量实际吞吐量。
class SpeedTestResult {
  final String ip;
  final int port;
  final double speedMBps;     // 下载速度 (MB/s)
  final int bytesDownloaded;  // 下载字节数
  final Duration duration;    // 耗时
}

class SpeedTester {
  /// 可选的下载源
  static const downloadSources = {
    'auto': '自动选择',
    'cf': 'https://speed.cloudflare.com/__down?bytes=10485760',
    'cm': 'http://test.ustc.edu.cn/backend/garbage.php?ckSize=10',
  };

  /// 单个 IP 速度测试
  static Future<SpeedTestResult?> testSingle(
    String ip, int port, {
    Duration timeout = const Duration(seconds: 15),
    String sourceUrl = 'auto',
  }) async {
    // 1. 通过 Dio 下载 sourceUrl，设置 proxy 到 ip:port
    // 2. 计算下载速度 = bytesReceived / elapsedSeconds
    // 3. 返回结果
  }

  /// 批量速度测试（并发控制）
  static Future<List<SpeedTestResult>> testBatch(
    List<String> ips, int port, {
    int workers = 5,
    Duration timeout = const Duration(seconds: 15),
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async { ... }
}
```

#### 4. 扫描状态管理 (`scanner_state.dart`)

```dart
/// 扫描模式
enum ScanMode { tcpPing, httpPing }

/// 扫描来源
enum ScanSource { cfRange, customList }

/// 速度测试状态
class SpeedTestProgress { ... }

/// 扫描状态
class ScannerState {
  final bool scanning;
  final bool speedTesting;
  final ScanMode scanMode;
  final ScanSource scanSource;
  final List<LatencyResult> results;
  final List<SpeedTestResult> speedResults;
  final LatencyProgress? progress;
  final SpeedTestProgress? speedProgress;
  final String? error;
}

/// 扫描通知器
class ScannerNotifier extends StateNotifier<ScannerState> {
  /// 延迟扫描（支持 TCPing 和 HTTPing）
  Future<void> runLatencyScan({
    required ScanMode mode,
    required ScanSource source,
    List<String>? customIps,
    required int port,
    required int workers,
    required int probes,
    required Duration timeout,
    required double maxLatency,
  }) async { ... }

  /// 速度测试（对已扫描结果中的 IP）
  Future<void> runSpeedTest({
    required int workers,
    required Duration timeout,
    required String sourceUrl,
    double? minSpeedMBps,
  }) async { ... }

  void cancel() { ... }
}
```

#### 5. 扫描页 UI (`scanner_tab.dart`)

UI 布局分为三个区域：

**顶部：扫描模式选择**
- SegmentedButton: TCPing / HTTPing
- SegmentedButton: 官方CF段 / 自定义列表

**中部：参数配置**（根据选择动态显示）
- 端口 (默认 443)
- 并发数 (默认 100)
- 探测次数 (默认 3)
- 延迟阈值 (默认 300ms)
- 如果是自定义列表：文件选择或 URL 输入
- 「开始扫描」按钮

**底部：结果展示**
- 扫描结果表格（IP / 端口 / 延迟 / 抖动 / 国家 / 数据中心）
- 统计卡片（总数 / 通过 / 最低延迟）
- 国家/数据中心分布
- 「速度测试」按钮（对筛选后的结果测速）
- 速度测试结果列（速度 MB/s）
- 「导出」和「推送到 GitHub」按钮

#### 6. Tab 集成

在 `app.dart` 中：
- 添加第 6 个 `NavigationRailDestination` / `NavigationDestination`（图标：`Icons.radar`，标签：「扫描」）
- 在 `IndexedStack` 中添加 `ScannerTab()`
- `nextTab()`/`prevTab()` 的 modulo 从 5 改为 6
- 在 `shortcuts.dart` 中添加 `Ctrl+6` → `SwitchTabIntent(5)`

### 实施顺序

1. **Phase 1**: `cf_range_scanner.dart` + `http_ping.dart` + 测试（纯 core 层，不影响 UI）
2. **Phase 2**: `speed_test.dart` + 测试
3. **Phase 3**: `scanner_state.dart`（状态管理）
4. **Phase 4**: `scanner_tab.dart` + UI 组件
5. **Phase 5**: Tab 集成到 `app.dart` + 快捷键
6. **Phase 6**: 测试验证 + 构建运行

### 设计原则

- **不删现有功能**：所有现有 Tab 和功能完全保留
- **复用现有基础设施**：`latencyProbeAll` 的 `probe` 参数直接传入 `measureHttpTtfb`，复用并发控制、进度回调、取消机制
- **独立状态管理**：`ScannerNotifier` 与 `SubscriptionsNotifier` 并行，互不干扰
- **结果互通**：扫描结果可以通过「导出」或「推送 GitHub」与现有结果管线对接