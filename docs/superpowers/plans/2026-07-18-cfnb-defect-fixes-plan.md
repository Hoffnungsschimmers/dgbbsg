# CFNB App 缺陷全面修复 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复静态审查发现的全部缺陷，并把 GitHub 推送收敛为「只推 `.top` 后缀文件」，同时清理 AppConfig 中约 60% 的死字段与其 UI/迁移代码。

**Architecture:** 保持「订阅IP → 延迟优选 → 手动推送 GitHub」三步流程不变。所有改动集中在 `lib/core/{config,latency,speed,subscription,github}`、`lib/features/{subscriptions,results,settings}` 及 `test/**`。AppConfig 精简为仅含活字段；推送按钮固定推 `subLatencyOutputFile`（默认 `addressesapi_top.txt`，`.top` 后缀）；结果页展示国家（修正 `US@CM` 错显）与最高质量分 Q。

**Tech Stack:** Flutter 3.44.6 / Dart 3.12.2，`dio` 网络，`flutter_riverpod` 状态，`flutter_test` 单测，`shared_preferences` 持久化。

## Global Constraints

- 延迟测法保持裸 TCP RTT（不接入 `measureTlsLatency`）。
- 默认 `subNodeUuid` 改为合法 v4 形态占位：`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`（y∈{8,9,a,b}）。
- 死字段从 AppConfig、`settings_fields.dart`、`config_repository.dart` 迁移、测试里彻底删除；SharedPreferences 旧键读时忽略（向后兼容，不报错）。
- GitHub 推送**只**接受后缀为 `.top` 的文件；非 `.top` 直接返回失败且不发请求。
- 每个 task 结束需 `flutter analyze`（无 error/warning）与 `flutter test`（相关用例通过），并独立 commit。

---

### Task 1: AppConfig 删除死字段 + 新增活字段

**Files:**
- Modify: `lib/core/config/app_config.dart`（全文）
- Modify: `test/core/config/app_config_test.dart`

**Interfaces:**
- Produces: 精简后的 `AppConfig` 构造/`fromJson`/`toJson`/`copyWith`/`validate`，含新字段 `subLatencyProbes`（int，默认 3）。保留活字段见下。
- 活字段最终清单（其余全部删除）：
  `subConvertEnabled, subInputMode, subUrls, subNodeHost, subNodeUuid, subGenerators, subDisabledGenerators, subOutputFile, subDefaultCountry, subResolveDomain, subFetchTimeout, subFetchConnectTimeout, subFetchMaxRetries, subFetchRetryDelay, subResolveWorkers, subLatencyMaxMs, subLatencyOutputFile, subLatencyTimeout, subLatencyWorkers, subLatencyProbes, subLatencySni, subSpeedEnabled, subSpeedLatencyLimit, subSpeedTimeout, subSpeedSizeMb, subSpeedWorkers, subQualityLatencyWeight, githubToken, githubRepo, githubBranch, guiTheme, additionalSources`

- [ ] **Step 1: 写失败测试（验证不再包含死字段、含新字段）**

修改 `test/core/config/app_config_test.dart`，替换 default 断言组与 validate 组：

```dart
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig defaults', () {
    final c = const AppConfig();

    test('has expected default values', () {
      expect(c.guiTheme, 'light');
      expect(c.subInputMode, 'both');
      expect(c.subConvertEnabled, isTrue);
      expect(c.subNodeUuid, 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx');
      expect(c.subDefaultCountry, '');
      expect(c.subLatencyProbes, 3);
      expect(c.subLatencyOutputFile, 'addressesapi_top.txt');
      expect(c.subSpeedEnabled, isTrue);
      expect(c.githubRepo, 'Hoffnungsschimmers/cf-ip');
    });

    test('dead fields removed', () {
      // 编译期保证：以下字段不应存在
      expect(c is AppConfig, isTrue);
    });

    test('toJson then fromJson is stable', () {
      final json = c.toJson();
      final round = AppConfig.fromJson(json);
      expect(round.subDisabledGenerators, c.subDisabledGenerators);
      expect(round.additionalSources, c.additionalSources);
      expect(round.subGenerators, c.subGenerators);
      expect(round.subLatencyProbes, c.subLatencyProbes);
    });
  });

  group('AppConfig.fromJson parsing', () {
    test('parses additional sources list', () {
      final c = AppConfig.fromJson({
        'ADDITIONAL_SOURCES': [
          {'url': 'https://a.example/nodes', 'enabled': false},
        ]
      });
      expect(c.additionalSources.length, 1);
      expect(c.additionalSources.first.url, 'https://a.example/nodes');
      expect(c.additionalSources.first.enabled, false);
    });

    test('parses disabled generators set', () {
      final c = AppConfig.fromJson({
        'SUB_DISABLED_GENERATORS': ['CM', 'HK'],
      });
      expect(c.subDisabledGenerators, {'CM', 'HK'});
    });

    test('ignores unknown legacy keys without throwing', () {
      final c = AppConfig.fromJson({
        'CF_API_TOKEN': 'x',
        'ASN_SOURCES': [1],
        'SUB_NODE_UUID': 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx',
      });
      expect(c.subNodeUuid, 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx');
    });
  });

  group('AppConfig.validate', () {
    test('accepts defaults', () {
      expect(const AppConfig().validate(), isEmpty);
    });

    test('rejects bad sub input mode', () {
      final bad = AppConfig.fromJson({'SUB_INPUT_MODE': 'xxx'});
      expect(bad.validate(), isNotEmpty);
    });
  });

  group('AppConfig.copyWith', () {
    test('updates single field without touching others', () {
      final c = const AppConfig();
      final updated = c.copyWith(guiTheme: 'dark', subLatencyProbes: 5);
      expect(updated.guiTheme, 'dark');
      expect(updated.subLatencyProbes, 5);
      expect(updated.subInputMode, c.subInputMode);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认编译失败（死字段引用）**

Run: `cd D:\env\cfnb_app && flutter test test/core/config/app_config_test.dart 2>&1 | Select-Object -First 20`
Expected: 编译错误（引用了已删除字段如 `globalTopN`、`outputFile`）。

- [ ] **Step 3: 重写 app_config.dart 为精简版**

用以下内容完整替换 `lib/core/config/app_config.dart`（保留 `SourceConfig` / `defaultAdditionalSources` / `defaultSubGenerators`；`defaultAdditionalSources` 移除硬编码本地路径行 `'D:\\env\\cfnb\\cfdata_ips.txt'`）：

```dart
/// 应用配置模型（仅保留「订阅转换 → 延迟优选 → 推送 GitHub」三步流程所需字段）。
///
/// 普通 Dart class + 手写 fromJson/toJson，避免 codegen 复杂度。所有字段带默认值，
/// 等价于旧版 Python config.Config 的 pydantic Field(default=...)。SharedPreferences
/// 中的旧键（CF DNS / WxPusher / ASN / 可用性 / 广告 / 旧筛选等）读时忽略，向后兼容。
class AppConfig {
  // ============ 订阅转换 ============
  final bool subConvertEnabled;
  final String subInputMode;
  final List<String> subUrls;
  final String subNodeHost;
  final String subNodeUuid;
  final List<String> subGenerators;
  final Set<String> subDisabledGenerators;
  final String subOutputFile;
  final String subDefaultCountry;
  final bool subResolveDomain;
  final int subFetchTimeout;
  final int subFetchConnectTimeout;
  final int subFetchMaxRetries;
  final int subFetchRetryDelay;
  final int subResolveWorkers;

  // ============ 延迟优选 ============
  final int subLatencyMaxMs;
  final String subLatencyOutputFile;
  final double subLatencyTimeout;
  final int subLatencyWorkers;
  final int subLatencyProbes;
  final String subLatencySni;

  // ============ 带宽测速 ============
  final bool subSpeedEnabled;
  final int subSpeedLatencyLimit; // 仅对延迟 ≤ 该值(ms)的节点测带宽
  final double subSpeedTimeout;
  final double subSpeedSizeMb;
  final int subSpeedWorkers;
  final double subQualityLatencyWeight; // 综合优选延迟权重(0-1)，带宽权重 = 1 - 该值

  // ============ GitHub 推送（独立 cf-ip 仓） ============
  final String githubToken;
  final String githubRepo;
  final String githubBranch;

  // ============ 外观 ============
  final String guiTheme;

  // ============ 数据源（仅 url 列表，供 UI 编辑） ============
  final List<SourceConfig> additionalSources;

  const AppConfig({
    this.subConvertEnabled = true,
    this.subInputMode = 'both',
    this.subUrls = const [],
    this.subNodeHost = 'example.com',
    this.subNodeUuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx',
    this.subGenerators = defaultSubGenerators,
    this.subDisabledGenerators = const {},
    this.subOutputFile = 'addressesapi.txt',
    this.subDefaultCountry = '',
    this.subResolveDomain = true,
    this.subFetchTimeout = 20,
    this.subFetchConnectTimeout = 10,
    this.subFetchMaxRetries = 3,
    this.subFetchRetryDelay = 3,
    this.subResolveWorkers = 32,
    this.subLatencyMaxMs = 200,
    this.subLatencyOutputFile = 'addressesapi_top.txt',
    this.subLatencyTimeout = 3.0,
    this.subLatencyWorkers = 50,
    this.subLatencyProbes = 3,
    this.subLatencySni = 'sdtbu.campusblog.ccwu.cc',
    this.subSpeedEnabled = true,
    this.subSpeedLatencyLimit = 200,
    this.subSpeedTimeout = 20.0,
    this.subSpeedSizeMb = 10.0,
    this.subSpeedWorkers = 10,
    this.subQualityLatencyWeight = 0.6,
    this.githubToken = '',
    this.githubRepo = 'Hoffnungsschimmers/cf-ip',
    this.githubBranch = 'main',
    this.guiTheme = 'light',
    this.additionalSources = defaultAdditionalSources,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    T pick<T>(String key, T fallback) {
      final v = json[key];
      return v is T ? v : fallback;
    }
    List<int> pickIntList(String key, List<int> fallback) {
      final v = json[key];
      if (v is List) return v.map((e) => int.tryParse(e.toString()) ?? 0).toList();
      if (v is String) {
        return v.split(',').where((s) => s.trim().isNotEmpty).map((s) => int.tryParse(s.trim()) ?? 0).toList();
      }
      return fallback;
    }
    List<String> pickStrList(String key, List<String> fallback) {
      final v = json[key];
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String) return v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      return fallback;
    }
    Set<String> pickStrSet(String key, Set<String> fallback) {
      final v = json[key];
      if (v is List) return v.map((e) => e.toString()).toSet();
      return fallback;
    }
    List<SourceConfig> pickSources(String key, List<SourceConfig> fallback) {
      final v = json[key];
      if (v is List) return v.whereType<Map<String, dynamic>>().map(SourceConfig.fromJson).toList();
      return fallback;
    }
    return AppConfig(
      subConvertEnabled: pick('SUB_CONVERT_ENABLED', true),
      subInputMode: pick('SUB_INPUT_MODE', 'both'),
      subUrls: pickStrList('SUB_URLS', const []),
      subNodeHost: pick('SUB_NODE_HOST', 'example.com'),
      subNodeUuid: pick('SUB_NODE_UUID', 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'),
      subGenerators: pickStrList('SUB_GENERATORS', const []),
      subDisabledGenerators: pickStrSet('SUB_DISABLED_GENERATORS', const {}),
      subOutputFile: pick('SUB_OUTPUT_FILE', 'addressesapi.txt'),
      subDefaultCountry: pick('SUB_DEFAULT_COUNTRY', ''),
      subResolveDomain: pick('SUB_RESOLVE_DOMAIN', true),
      subFetchTimeout: pick('SUB_FETCH_TIMEOUT', 20),
      subFetchConnectTimeout: pick('SUB_FETCH_CONNECT_TIMEOUT', 10),
      subFetchMaxRetries: pick('SUB_FETCH_MAX_RETRIES', 3),
      subFetchRetryDelay: pick('SUB_FETCH_RETRY_DELAY', 3),
      subResolveWorkers: pick('SUB_RESOLVE_WORKERS', 32),
      subLatencyMaxMs: pick('SUB_LATENCY_MAX_MS', 200),
      subLatencyOutputFile: pick('SUB_LATENCY_OUTPUT_FILE', 'addressesapi_top.txt'),
      subLatencyTimeout: (pick('SUB_LATENCY_TIMEOUT', 3.0) as num).toDouble(),
      subLatencyWorkers: pick('SUB_LATENCY_WORKERS', 50),
      subLatencyProbes: pick('SUB_LATENCY_PROBES', 3),
      subLatencySni: pick('SUB_LATENCY_SNI', 'sdtbu.campusblog.ccwu.cc'),
      subSpeedEnabled: pick('SUB_SPEED_ENABLED', true),
      subSpeedLatencyLimit: pick('SUB_SPEED_LATENCY_LIMIT', 200),
      subSpeedTimeout: (pick('SUB_SPEED_TIMEOUT', 20.0) as num).toDouble(),
      subSpeedSizeMb: (pick('SUB_SPEED_SIZE_MB', 10.0) as num).toDouble(),
      subSpeedWorkers: pick('SUB_SPEED_WORKERS', 10),
      subQualityLatencyWeight: (pick('SUB_QUALITY_LATENCY_WEIGHT', 0.6) as num).toDouble(),
      githubToken: pick('GITHUB_TOKEN', ''),
      githubRepo: pick('GITHUB_REPO', 'Hoffnungsschimmers/cf-ip'),
      githubBranch: pick('GITHUB_BRANCH', 'main'),
      guiTheme: pick('GUI_THEME', 'light'),
      additionalSources: pickSources('ADDITIONAL_SOURCES', const []),
    );
  }

  Map<String, dynamic> toJson() => {
        'SUB_CONVERT_ENABLED': subConvertEnabled,
        'SUB_INPUT_MODE': subInputMode,
        'SUB_URLS': subUrls,
        'SUB_NODE_HOST': subNodeHost,
        'SUB_NODE_UUID': subNodeUuid,
        'SUB_GENERATORS': subGenerators,
        'SUB_DISABLED_GENERATORS': subDisabledGenerators.toList(),
        'SUB_OUTPUT_FILE': subOutputFile,
        'SUB_DEFAULT_COUNTRY': subDefaultCountry,
        'SUB_RESOLVE_DOMAIN': subResolveDomain,
        'SUB_FETCH_TIMEOUT': subFetchTimeout,
        'SUB_FETCH_CONNECT_TIMEOUT': subFetchConnectTimeout,
        'SUB_FETCH_MAX_RETRIES': subFetchMaxRetries,
        'SUB_FETCH_RETRY_DELAY': subFetchRetryDelay,
        'SUB_RESOLVE_WORKERS': subResolveWorkers,
        'SUB_LATENCY_MAX_MS': subLatencyMaxMs,
        'SUB_LATENCY_OUTPUT_FILE': subLatencyOutputFile,
        'SUB_LATENCY_TIMEOUT': subLatencyTimeout,
        'SUB_LATENCY_WORKERS': subLatencyWorkers,
        'SUB_LATENCY_PROBES': subLatencyProbes,
        'SUB_LATENCY_SNI': subLatencySni,
        'SUB_SPEED_ENABLED': subSpeedEnabled,
        'SUB_SPEED_LATENCY_LIMIT': subSpeedLatencyLimit,
        'SUB_SPEED_TIMEOUT': subSpeedTimeout,
        'SUB_SPEED_SIZE_MB': subSpeedSizeMb,
        'SUB_SPEED_WORKERS': subSpeedWorkers,
        'SUB_QUALITY_LATENCY_WEIGHT': subQualityLatencyWeight,
        'GITHUB_TOKEN': githubToken,
        'GITHUB_REPO': githubRepo,
        'GITHUB_BRANCH': githubBranch,
        'GUI_THEME': guiTheme,
        'ADDITIONAL_SOURCES': additionalSources.map((s) => s.toJson()).toList(),
      };

  AppConfig copyWith({
    bool? subConvertEnabled,
    String? subInputMode,
    List<String>? subUrls,
    String? subNodeHost,
    String? subNodeUuid,
    List<String>? subGenerators,
    Set<String>? subDisabledGenerators,
    String? subOutputFile,
    String? subDefaultCountry,
    bool? subResolveDomain,
    int? subFetchTimeout,
    int? subFetchConnectTimeout,
    int? subFetchMaxRetries,
    int? subFetchRetryDelay,
    int? subResolveWorkers,
    int? subLatencyMaxMs,
    String? subLatencyOutputFile,
    double? subLatencyTimeout,
    int? subLatencyWorkers,
    int? subLatencyProbes,
    String? subLatencySni,
    bool? subSpeedEnabled,
    int? subSpeedLatencyLimit,
    double? subSpeedTimeout,
    double? subSpeedSizeMb,
    int? subSpeedWorkers,
    double? subQualityLatencyWeight,
    String? githubToken,
    String? githubRepo,
    String? githubBranch,
    String? guiTheme,
    List<SourceConfig>? additionalSources,
  }) {
    return AppConfig(
      subConvertEnabled: subConvertEnabled ?? this.subConvertEnabled,
      subInputMode: subInputMode ?? this.subInputMode,
      subUrls: subUrls ?? this.subUrls,
      subNodeHost: subNodeHost ?? this.subNodeHost,
      subNodeUuid: subNodeUuid ?? this.subNodeUuid,
      subGenerators: subGenerators ?? this.subGenerators,
      subDisabledGenerators: subDisabledGenerators ?? this.subDisabledGenerators,
      subOutputFile: subOutputFile ?? this.subOutputFile,
      subDefaultCountry: subDefaultCountry ?? this.subDefaultCountry,
      subResolveDomain: subResolveDomain ?? this.subResolveDomain,
      subFetchTimeout: subFetchTimeout ?? this.subFetchTimeout,
      subFetchConnectTimeout: subFetchConnectTimeout ?? this.subFetchConnectTimeout,
      subFetchMaxRetries: subFetchMaxRetries ?? this.subFetchMaxRetries,
      subFetchRetryDelay: subFetchRetryDelay ?? this.subFetchRetryDelay,
      subResolveWorkers: subResolveWorkers ?? this.subResolveWorkers,
      subLatencyMaxMs: subLatencyMaxMs ?? this.subLatencyMaxMs,
      subLatencyOutputFile: subLatencyOutputFile ?? this.subLatencyOutputFile,
      subLatencyTimeout: subLatencyTimeout ?? this.subLatencyTimeout,
      subLatencyWorkers: subLatencyWorkers ?? this.subLatencyWorkers,
      subLatencyProbes: subLatencyProbes ?? this.subLatencyProbes,
      subLatencySni: subLatencySni ?? this.subLatencySni,
      subSpeedEnabled: subSpeedEnabled ?? this.subSpeedEnabled,
      subSpeedLatencyLimit: subSpeedLatencyLimit ?? this.subSpeedLatencyLimit,
      subSpeedTimeout: subSpeedTimeout ?? this.subSpeedTimeout,
      subSpeedSizeMb: subSpeedSizeMb ?? this.subSpeedSizeMb,
      subSpeedWorkers: subSpeedWorkers ?? this.subSpeedWorkers,
      subQualityLatencyWeight: subQualityLatencyWeight ?? this.subQualityLatencyWeight,
      githubToken: githubToken ?? this.githubToken,
      githubRepo: githubRepo ?? this.githubRepo,
      githubBranch: githubBranch ?? this.githubBranch,
      guiTheme: guiTheme ?? this.guiTheme,
      additionalSources: additionalSources ?? this.additionalSources,
    );
  }

  /// 校验配置合法性。返回错误字符串列表，为空表示通过。
  List<String> validate() {
    final errors = <String>[];
    if (!['node', 'url', 'both'].contains(subInputMode)) {
      errors.add("SUB_INPUT_MODE 必须是 'node'、'url' 或 'both'");
    }
    return errors;
  }
}

class SourceConfig {
  final String url;
  final bool enabled;

  const SourceConfig({required this.url, this.enabled = true});

  factory SourceConfig.fromJson(Map<String, dynamic> json) => SourceConfig(
        url: json['url']?.toString() ?? '',
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      );

  Map<String, dynamic> toJson() => {'url': url, 'enabled': enabled};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceConfig && other.url == url && other.enabled == enabled;

  @override
  int get hashCode => url.hashCode ^ enabled.hashCode;
}

// 默认数据源：edgetunnel 生态常用优选源（公开聚合器）。
const List<SourceConfig> defaultAdditionalSources = [
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/us.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/tw.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/jp.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/hk.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/sg.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/kr.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/mini.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng2/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng2/mini.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng3/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/Cfxyz.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/SG.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/DE.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/US.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/wetest/ipv4.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/wetest/ipv6.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/cfyes/ipv4.txt'),
  SourceConfig(url: 'https://cf.junzhen.qzz.io/best_ips.txt'),
  SourceConfig(url: 'https://cf.junzhen.qzz.io/best_ips_bj.txt'),
  SourceConfig(url: 'https://cf.090227.xyz/ct?ips=6'),
  SourceConfig(url: 'https://cf.090227.xyz/cu'),
  SourceConfig(url: 'https://cf.090227.xyz/cmcc?ips=8'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=all&ips=20'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=ct&ips=50'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=cu&ips=50'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=cmcc&ips=50'),
  SourceConfig(url: 'https://bestcf.pages.dev/vps789/top20.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/vps789/top50.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/vps789/top100.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/tw.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/hk.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/jp.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/kr.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/sg.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/us.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/cmliu/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/cmliu2/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/lzj/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/lajiao/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/kristi/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/idk/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/moistr/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/ircf/ipv4.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/uouin/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/luoli/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/zhixuanwang/ipv4-onlyip.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/ygkkk/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/qms/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/fiatnorm/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/senflare/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/wuya/all.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/gshtwy/CF-DNS-Clone/refs/heads/main/wetest-cloudflare-v4.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/ymyuuu/IPDB/refs/heads/main/BestCF/bestcfv4.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/ymyuuu/IPDB/refs/heads/main/BestCF/bestcfv6.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/joname1/BestCFip/refs/heads/main/ipv4.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/Senflare/Senflare-IP/refs/heads/main/IPlist-Pro.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/einsitang/my-fast-cf-ip/refs/heads/master/fastips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/hubbylei/bestcf/refs/heads/main/bestcf.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/love-ztm/cfip/refs/heads/main/best_ips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/love-ztm/cfip/refs/heads/main/ubest_ips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/svip-s/cloudflare_ip/refs/heads/main/best_ips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/yuanxiawan/cfipv4db/refs/heads/main/cfip.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/WARP/WARP-MASQUE-IPs-443.txt', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=all&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=198&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=197&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=193&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=192&port=443', enabled: false),
  SourceConfig(url: 'https://addressesapi.090227.xyz/CloudFlareYes'),
  SourceConfig(url: 'https://zip.cm.edu.kg/all.txt'),
  SourceConfig(url: 'https://countrymerge.pages.dev/all.txt'),
  SourceConfig(url: 'https://sub.pjq.cc/cd'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/mini.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/Domain-TOP.txt'),
  SourceConfig(url: 'https://randomip.pages.dev/?c=162.159.38.0/24&n=50&p=443', enabled: false),
  SourceConfig(url: 'https://randomip.pages.dev/?c=172.64.0.0/13&n=50&p=random', enabled: false),
  SourceConfig(url: 'https://bestcf.pages.dev/entryip/50.txt', enabled: false),
];

// 默认订阅器（格式：名称|域名）。
const List<String> defaultSubGenerators = [
  'IDK|sub.pjq.cc.cd',
  'CM|sub.cmliussss.net',
  'Moist_R|owo.o00o.ooo',
  '洛璃|loli.sub.us.ci',
  '辣子鸡|sub.lzjbaby.com',
  '辣椒炒肉少放辣|sub.xdu.qzz.io',
  'S5公益|sub.995677.xyz',
  '文烨|sub.keaeye.icu',
  'Kristi|sub.mot.cloudns.biz',
  '天诚|cm.soso.edu.kg',
];
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd D:\env\cfnb_app && flutter test test/core/config/app_config_test.dart 2>&1 | Select-Object -First 20`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
cd D:\env\cfnb_app && git add lib/core/config/app_config.dart test/core/config/app_config_test.dart && git commit -q -m "refactor(config): drop dead fields, add subLatencyProbes, v4 uuid default"
```

---

### Task 2: config_repository 迁移精简

**Files:**
- Modify: `lib/core/config/config_repository.dart`
- Modify: `test/core/config/app_config_test.dart`（无需改，仅确认不回归）

**Interfaces:**
- Consumes: 精简后的 `AppConfig`（Task 1）。
- Produces: `ConfigRepository.init()` 仅保留：空 `additionalSources`/`subGenerators` 补默认；`subSpeed*` 升级；`subLatencyMaxMs==0→200`、`subSpeedLatencyLimit==0→200`；旧 `SUB_DEFAULT_COUNTRY=='UN'` → `''`。删除 `SUB_LATENCY_TOPN` 迁移。

- [ ] **Step 1: 替换 config_repository.dart 的 init 迁移逻辑**

完整替换 `lib/core/config/config_repository.dart`：

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_config.dart' show defaultAdditionalSources, defaultSubGenerators;

/// 配置持久化仓库。内存持有当前 [AppConfig]（单例语义）。
/// 启动时从 shared_preferences 读取；不存在则用默认值。旧键忽略，向后兼容。
class ConfigRepository {
  AppConfig _config;
  final SharedPreferences _prefs;

  ConfigRepository._(this._config, this._prefs);

  static Future<ConfigRepository> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kConfigJson);
    final Map<String, dynamic> data = jsonStr != null
        ? (jsonDecode(jsonStr) as Map<String, dynamic>)
        : <String, dynamic>{};
    var config = data.isNotEmpty ? AppConfig.fromJson(data) : const AppConfig();
    var dirty = false;

    // 迁移：旧配置若没有数据源，补入默认源。
    if (config.additionalSources.isEmpty) {
      config = config.copyWith(
        additionalSources: defaultAdditionalSources,
        subGenerators: defaultSubGenerators,
      );
      dirty = true;
    }

    // 迁移：旧默认国家 UN 视为未配置，改为空串（由节点名国家码决定）。
    if (config.subDefaultCountry.toUpperCase() == 'UN') {
      config = config.copyWith(subDefaultCountry: '');
      dirty = true;
    }

    // 迁移：带宽测速参数升级为更真实的默认值（仅当用户仍用旧默认值时生效）。
    if (config.subSpeedSizeMb == 1.0) {
      config = config.copyWith(subSpeedSizeMb: 10.0);
      dirty = true;
    }
    if (config.subSpeedTimeout == 15.0) {
      config = config.copyWith(subSpeedTimeout: 20.0);
      dirty = true;
    }
    if (config.subSpeedWorkers == 20) {
      config = config.copyWith(subSpeedWorkers: 10);
      dirty = true;
    }
    if (config.subLatencyTimeout == 2.0) {
      config = config.copyWith(subLatencyTimeout: 3.0);
      dirty = true;
    }
    if (config.subLatencyMaxMs == 0) {
      config = config.copyWith(subLatencyMaxMs: 200);
      dirty = true;
    }
    if (config.subSpeedLatencyLimit == 0) {
      config = config.copyWith(subSpeedLatencyLimit: 200);
      dirty = true;
    }

    if (dirty) {
      await prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
    }

    return ConfigRepository._(config, prefs);
  }

  static const _kConfigJson = 'app_config_json';

  AppConfig get current => _config;

  Future<void> save(AppConfig config) async {
    _config = config;
    await _prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
  }

  Future<void> update(AppConfig config) => save(config);

  List<String> validateCurrent() => _config.validate();
}
```

- [ ] **Step 2: 运行 analyze + 现有测试**

Run: `cd D:\env\cfnb_app && flutter analyze lib/core/config/config_repository.dart 2>&1 | Select-Object -First 10`
Expected: 无 error/warning（可能残留对 `defaultAdditionalSources` 的 `unnecessary_import` 提示——因第二次 `import` 仅为 `show`，删除该 import 行即可）。

修复：若 `analyze` 报 `unnecessary_import`，删除 `config_repository.dart` 第 6 行 `import 'app_config.dart' show defaultAdditionalSources, defaultSubGenerators;`（Task1 已在同一文件 import）。

- [ ] **Step 3: 运行全量 config 测试**

Run: `cd D:\env\cfnb_app && flutter test test/core/config 2>&1 | Select-Object -First 15`
Expected: PASS。

- [ ] **Step 4: Commit**

```bash
cd D:\env\cfnb_app && git add lib/core/config/config_repository.dart && git commit -q -m "refactor(config): simplify repository migration, drop legacy keys"
```

---

### Task 3: latency_prober 空源 + nodeCountry 修正

**Files:**
- Modify: `lib/core/latency/latency_prober.dart`（无需改，`nodeCountry` 已是按 `@` split，已正确）
- Modify: `lib/core/subscription/subscription_converter.dart`（写节点时空 `cc` 不拼 `#`）
- Modify: `test/core/latency/latency_test.dart`（已正确：测试 `nodeCountry('...#JP@CM')=='JP'`）

**Interfaces:**
- Consumes: `parser.extractCountryCode`（Task 无改动）。
- Produces: `convertSubscriptions` 在 `cc` 为空时写 `ip:port` 而非 `ip:port#`。

- [ ] **Step 1: 验证 nodeCountry 行为已正确**

`latency_prober.dart` 的 `nodeCountry` 当前实现：
```dart
String nodeCountry(String node) {
  final comment = node.contains('#') ? node.split('#')[1] : '';
  return comment.split('@').first.trim();
}
```
对 `'1.2.3.4:443#US@CM'` 返回 `'US'`，已正确，无需改。

- [ ] **Step 2: 修改 convertSubscriptions 的节点拼接（空国家不写 #）**

在 `lib/core/subscription/subscription_converter.dart` `convertSubscriptions` 中，定位 `final node = '$ip:${r.port}#$cc';`，改为：

```dart
        final cc = parser.extractCountryCode(r.name) ?? defaultCc;
        final node = cc.isEmpty ? '$ip:${r.port}' : '$ip:${r.port}#$cc';
```

- [ ] **Step 3: 更新 subscription_converter_test 的回落断言**

`test/core/subscription/subscription_converter_test.dart` 中旧断言 `expect(nodes.any((n) => n.startsWith('2.2.2.2:443#UN')), isTrue);`（第 89 行）改为空国家：

```dart
      expect(nodes.any((n) => n.startsWith('2.2.2.2:443')), isTrue);
```

- [ ] **Step 4: 运行测试**

Run: `cd D:\env\cfnb_app && flutter test test/core/subscription/subscription_converter_test.dart test/core/latency/latency_test.dart 2>&1 | Select-Object -First 20`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd D:\env\cfnb_app && git add lib/core/subscription/subscription_converter.dart test/core/subscription/subscription_converter_test.dart && git commit -q -m "fix(subscription): omit country suffix when country unknown"
```

---

### Task 4: LatencyFilter 加 maxKeep 上限

**Files:**
- Modify: `lib/core/latency/latency_filter.dart`
- Modify: `test/core/latency/latency_test.dart`

**Interfaces:**
- Consumes: `measureBandwidthAll`、`parseEndpoint`、`nodeCountry`（Task 1/3 已就绪）。
- Produces: `LatencyFilter.run` 新增 `int maxKeep = 200` 参数，在 `withinMax` 排序后 `take(maxKeep)`。

- [ ] **Step 1: 写失败测试（maxKeep 截断）**

在 `latency_test.dart` 的 `LatencyFilter.run` group 末尾追加：

```dart
    test('respects maxKeep cap', () async {
      Future<(double?, int)> fake(String ip, int port, Duration _, {int probes = 1, String? sni}) async {
        return (int.parse(ip.split('.').last).toDouble(), 1);
      }
      final dir = await Directory.systemTemp.createTemp('cfnb_lat_');
      final out = '${dir.path}/top.txt';
      final nodes = List.generate(50, (i) => '10.0.0.$i:443#US');
      final (kept, tested, connected) = await LatencyFilter.run(
        nodes: nodes,
        outputFile: out,
        latencyMaxMs: 1000,
        timeout: const Duration(seconds: 2),
        workers: 5,
        maxKeep: 10,
        probe: fake,
      );
      expect(tested, 50);
      expect(connected, 50);
      expect(kept.length, 10);
      await dir.delete(recursive: true);
    });
```

- [ ] **Step 2: 运行确认失败（maxKeep 未定义）**

Run: `cd D:\env\cfnb_app && flutter test test/core/latency/latency_test.dart -p "maxKeep" 2>&1 | Select-Object -First 15`
Expected: 编译错误 `maxKeep` 不是命名参数。

- [ ] **Step 3: 在 latency_filter.dart 加入 maxKeep**

在 `LatencyFilter.run` 签名新增 `int maxKeep = 200,`（放在 `int speedWorkers = 10,` 之后），并将：

```dart
    final withinMax = connectedResults
        .where((r) => r.latencyMs! <= latencyMaxMs)
        .toList()
      ..sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
```

改为：

```dart
    final withinMax = connectedResults
        .where((r) => r.latencyMs! <= latencyMaxMs)
        .toList()
      ..sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    final capped = withinMax.take(maxKeep).toList();
```

并将后续所有用到 `withinMax` 的位置（带宽测速候选、质量排序、输出）改为 `capped`：

- `if (speedEnabled && withinMax.isNotEmpty)` → `if (speedEnabled && capped.isNotEmpty)`
- `final good = withinMax.where(...)` → `final good = capped.where(...)`
- `final pool = good.isNotEmpty ? good : withinMax;` → `final pool = good.isNotEmpty ? good : capped;`
- `final keptResults = withinMax.toList()` → `final keptResults = capped.toList()`

- [ ] **Step 4: 运行测试**

Run: `cd D:\env\cfnb_app && flutter test test/core/latency/latency_test.dart 2>&1 | Select-Object -First 20`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd D:\env\cfnb_app && git add lib/core/latency/latency_filter.dart test/core/latency/latency_test.dart && git commit -q -m "feat(latency): cap kept nodes with maxKeep"
```

---

### Task 5: subscription_converter fetchFirstWorking 并发 + 逐 URL 日志

**Files:**
- Modify: `lib/core/subscription/subscription_converter.dart`
- Modify: `test/core/subscription/subscription_converter_test.dart`

**Interfaces:**
- Consumes: `fetchSingle`、`SubParser.parseSubscriptionLinks`、`decodeSubscription`。
- Produces: `fetchFirstWorking` 并发；`convertSubscriptions` 逐 URL 失败日志。

- [ ] **Step 1: 写失败测试（并发取首个可用）**

在 `subscription_converter_test.dart` 的 `generatorFetchUrls` group 后追加 group：

```dart
  group('fetchFirstWorking', () {
    test('returns first url that yields nodes, concurrently', () async {
      int callCount = 0;
      Future<String> fetcher(String url) async {
        callCount++;
        if (url.contains('fail')) return '';
        return 'vless://u@host.com:443';
      }
      final urls = ['https://a/fail', 'https://b/fail', 'https://c/ok'];
      final res = await fetchFirstWorking(urls, fetcher);
      expect(res, contains('vless://'));
      expect(callCount, 3); // 并发：全部发起
    });
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `cd D:\env\cfnb_app && flutter test test/core/subscription/subscription_converter_test.dart -p "fetchFirstWorking" 2>&1 | Select-Object -First 15`
Expected: 现有 `fetchFirstWorking` 串行实现下 `callCount==3` 仍通过但非并发；本任务目标是并发，测试主要验证行为正确（返回首个可用），并发由实现保证。

- [ ] **Step 3: 改写 fetchFirstWorking 为并发**

替换 `subscription_converter.dart` 的 `fetchFirstWorking`：

```dart
/// 并发尝试候选 URL，返回第一个能解码出节点链接的订阅原文。
/// 都没节点时返回首个非空兜底。
Future<String> fetchFirstWorking(List<String> urls, SubFetcher fetch) async {
  if (urls.isEmpty) return '';
  final results = await Future.wait(urls.map((u) async {
    try {
      return await fetchSingle(u, fetch);
    } on Object catch (e) {
      return '__err__:$u:$e';
    }
  }));
  String? fallback;
  for (var i = 0; i < results.length; i++) {
    final content = results[i];
    if (content.startsWith('__err__:')) {
      // 逐 URL 记录失败明细（在 convertSubscriptions 的 onLog 外，这里只返回标记）
      continue;
    }
    if (content.isEmpty) continue;
    if (SubParser.parseSubscriptionLinks(decodeSubscription(content)).isNotEmpty) {
      return content;
    }
    fallback ??= content;
  }
  return fallback ?? '';
}
```

- [ ] **Step 4: 在 convertSubscriptions 加逐 URL 失败日志**

在 `convertSubscriptions` 的 `for (final content in bodies)` 循环内，`if (content.isEmpty) continue;` 之前追加记录（需拿到当前 url）：当前 `bodies` 由 `fetchFirstWorking` 返回单条，无法逐 URL。改为：在 `collectSubscriptionTasks` 的 node 模式里，本任务仅对 `fetchFirstWorking` 失败的 generator 在现有 `onLog?.call('[-] $name：所有 URL 均拉取失败或未解析出节点。')` 已覆盖；额外在 `fetchSingle` 内失败时直接 print 到 onLog。

为最小侵入：在 `convertSubscriptions` 调用 `fetchSingle`/`fetchFirstWorking` 时传入的 `fetch` 已是 `subscriptions_state._safeFetch`（已记录每次失败）。因此 逐 URL 日志已满足。本步骤仅确认 `fetchSingle` 在 `subscription_converter.dart` 中失败透传——无需改。

- [ ] **Step 5: 运行测试**

Run: `cd D:\env\cfnb_app && flutter test test/core/subscription/subscription_converter_test.dart 2>&1 | Select-Object -First 20`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
cd D:\env\cfnb_app && git add lib/core/subscription/subscription_converter.dart test/core/subscription/subscription_converter_test.dart && git commit -q -m "perf(subscription): fetchFirstWorking concurrent, keep per-url errors"
```

---

### Task 6: result_state 国家列修正 + 解析 Q

**Files:**
- Modify: `lib/features/results/result_state.dart`
- Modify: `test/features/settings_results_test.dart`（确认不回归）

**Interfaces:**
- Consumes: `nodeCountry`（Task 3）。
- Produces: `ResultRow.country` 改用 `nodeCountry()`；`parseResultLines` 解析行尾 `Qxx.xx` 存入 `quality` 字段。

- [ ] **Step 1: 写失败测试**

在 `test/features/settings_results_test.dart` 末尾追加（若文件结构允许，否则新建 `test/features/result_state_test.dart`）：

```dart
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResultRow.country', () {
    test('uses nodeCountry (splits at @)', () {
      expect(ResultRow('1.2.3.4:443#US@CM').country, 'US');
      expect(ResultRow('1.2.3.4:443#JP').country, 'JP');
      expect(ResultRow('1.2.3.4:443').country, '');
    });
  });
  group('parseResultLines Q', () {
    test('parses quality score', () {
      final rows = parseResultLines('1.2.3.4:443#US 12.34Mbps 50.00ms Q0.87');
      expect(rows.length, 1);
      expect(rows.first.quality, 0.87);
    });
    test('quality null when absent', () {
      final rows = parseResultLines('1.2.3.4:443#US 12.34Mbps 50.00ms');
      expect(rows.first.quality, isNull);
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd D:\env\cfnb_app && flutter test test/features/settings_results_test.dart 2>&1 | Select-Object -First 15` （或新文件）
Expected: 编译错误（`ResultRow.country` 取错 / `quality` 字段不存在）。

- [ ] **Step 3: 修改 result_state.dart**

- `ResultRow` 增加 `final double? quality;` 字段与构造参数；`country` getter 改用 `nodeCountry`：

```dart
import 'package:cfnb_app/core/latency/latency_prober.dart';

class ResultRow {
  final String node;
  final String? speed;
  final String? latency;
  final double? quality;
  ResultRow(this.node, [this.speed, this.latency, this.quality]);

  String get ipPort => node.split('#').first;
  String get country => nodeCountry(node);
}
```

- `parseResultLines` 中，识别 `Qxx.xx`（值+`Q` 前缀）：在 for 循环中 tokens 处理追加：

```dart
      String? quality;
      for (var i = 0; i < tokens.length; i++) {
        final p = tokens[i];
        if (p.contains('Mbps')) speed ??= (i > 0 ? '${tokens[i - 1]} $p' : p);
        if (p.contains('ms')) latency ??= (i > 0 ? '${tokens[i - 1]} $p' : p);
        if (p.startsWith('Q')) {
          final q = double.tryParse(p.substring(1));
          quality ??= q;
        }
      }
```

- `rows.add(ResultRow(node, speed, latency, quality));`

- [ ] **Step 4: 运行测试**

Run: `cd D:\env\cfnb_app && flutter test test/features/settings_results_test.dart 2>&1 | Select-Object -First 20`
Expected: PASS（新测试 + 既有测试）。

- [ ] **Step 5: Commit**

```bash
cd D:\env\cfnb_app && git add lib/features/results/result_state.dart test/features/settings_results_test.dart && git commit -q -m "fix(results): correct country column, parse quality score"
```

---

### Task 7: subscriptions_state 接入 subLatencyProbes + 收敛 Dio + 推送 .top 校验

**Files:**
- Modify: `lib/features/subscriptions/subscriptions_state.dart`
- Modify: `lib/core/github/github_push.dart`
- Modify: `test/core/github/github_push_test.dart`

**Interfaces:**
- Consumes: `GithubPush`（Task 1 后仍存在）、`LatencyFilter.run` 的 `probes` 参数（来自 `subLatencyProbes`）。
- Produces: `pushFile` 仅接受 `.top`；`runLatency` 透传 `subLatencyProbes`；共享直连 Dio（消除两 Dio 实例）。

- [ ] **Step 1: 写失败测试（pushFile 拒绝非 .top）**

在 `github_push_test.dart` 追加 group（注意：`pushFile` 在 `subscriptions_state`，但校验逻辑放在 `GithubPush` 之外。本任务把校验放在 `subscriptions_state.pushFile`，测试需经 `SubscriptionsNotifier`——较复杂。改为：在 `GithubPush` 中新增 `isPushable(String file)` 静态方法供复用，并测试它）：

```dart
  group('isPushable', () {
    test('only .top files', () {
      expect(GithubPush.isPushable('addressesapi_top.txt'), isTrue);
      expect(GithubPush.isPushable('addressesapi.txt'), isFalse);
      expect(GithubPush.isPushable('ip.txt'), isFalse);
    });
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `cd D:\env\cfnb_app && flutter test test/core/github/github_push_test.dart -p "isPushable" 2>&1 | Select-Object -First 10`
Expected: 编译错误 `isPushable` 未定义。

- [ ] **Step 3: 在 github_push.dart 加 isPushable + 修 Dio 创建**

- 在 `GithubPush` 类加静态方法：

```dart
  /// 仅允许推送后缀为 .top 的文件（优选结果），其余文件不推送。
  static bool isPushable(String file) =>
      file.toLowerCase().endsWith('.top');
```

- 将 `github_push.dart` 的 `onHttpClientCreate` 改为 `createHttpClient`（去 deprecation）。替换构造内的 adapter 块：

```dart
    final adapter = this.dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        client.userAgent = 'cfnb-app';
        return client;
      };
    }
```

（`createHttpClient` 返回 `HttpClient`，无需 onBadCertificate 因证书放宽在 TLS 层不需——GitHub API 走正常 TLS。若 `implementation_imports` 警告仍在，保留 `import 'package:dio/src/adapters/io_adapter.dart';`）

- [ ] **Step 4: 修改 subscriptions_state.dart**

  a) 顶部 import 增加 `import '../../core/github/github_push.dart';`（用于 `GithubPush.isPushable`）。删除 `import 'package:dio/src/adapters/io_adapter.dart';`（不再自己造 Dio adapter）。

  b) `pushFile` 入口加校验：

```dart
  Future<(bool, int, String)> pushFile(String file) async {
    if (!GithubPush.isPushable(file)) {
      final m = '仅支持推送后缀为 .top 的优选结果文件（当前：$file）';
      logger.info(m);
      return (false, 0, m);
    }
    final cfg = await _cfg();
    ...
  }
```

  c) `runLatency` 中把 `probes: 3,` 改为 `probes: cfg.subLatencyProbes,`。

  d) 删除 `subscriptions_state.dart` 内自建的 `_dio` 与 `_configureDio`/`_resolveProxy`/`_httpFetch` 中走代理的部分，改为复用 `GithubPush` 的直连 Dio。具体：在 `SubscriptionsNotifier` 新增字段 `final GithubPush _gh = GithubPush(token: '', repo: '', branch: '');` 不合适（token 运行时才知道）。改为暴露一个共享 Dio 工厂：

  - 在 `github_push.dart` 增加静态方法 `static Dio directDio()` 返回已配置直连+UA 的 Dio（baseUrl 空）。
  - `subscriptions_state.dart` 用 `final _dio = GithubPush.directDio();` 替换原 `_dio` 构造，并删除 `_configureDio()` 调用与 `_resolveProxy`、`_configureDio` 方法体（保留 `_httpFetch` 但无需手动设 proxy：`_dio` 已是直连）。

  注意：订阅抓取经本地代理（127.0.0.1:7890）可达源，但当前 `_resolveProxy` 默认回落 7890。用户环境 Clash 开 TUN + 系统代理，订阅源直连可达；为保持行为，**订阅抓取保留走系统代理**：在 `directDio()` 中不加 `findProxy='DIRECT'`，让 Dio 走系统代理（Flutter 默认）。GitHub 走直连（在 `GithubPush` 内部单独设 `DIRECT`）。因此 `directDio()` 不设置 `findProxy`，仅设 UA；`GithubPush` 内部构造仍显式 `DIRECT`。

  最终 `_httpFetch` 改为：

```dart
  Future<String> _httpFetch(String url, {Duration? connectTimeout}) async {
    final resp = await _dio.get(url,
        options: dio_pkg.Options(
          responseType: dio_pkg.ResponseType.plain,
          headers: {
            'User-Agent': edgetunnelUa,
            'Accept': '*/*',
          },
          connectTimeout: connectTimeout ?? const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ));
    return resp.data.toString();
  }
```

  并删除 `SubscriptionsNotifier` 构造里的 `_configureDio()` 调用、`_configureDio`、`_resolveProxy` 方法。

- [ ] **Step 5: 运行测试 + analyze**

Run: `cd D:\env\cfnb_app && flutter test test/core/github/github_push_test.dart 2>&1 | Select-Object -First 15`
Run: `cd D:\env\cfnb_app && flutter analyze lib/features/subscriptions/subscriptions_state.dart lib/core/github/github_push.dart 2>&1 | Select-Object -First 15`
Expected: 测试 PASS；analyze 无 error/warning（`implementation_imports` 若为 info 可接受，但尽量改为通过 `package:dio/dio.dart` 暴露的 adapter——若不可行保留）。

- [ ] **Step 6: Commit**

```bash
cd D:\env\cfnb_app && git add lib/features/subscriptions/subscriptions_state.dart lib/core/github/github_push.dart test/core/github/github_push_test.dart && git commit -q -m "fix(push): only .top files; share direct dio; use subLatencyProbes"
```

---

### Task 8: results_page 去文件下拉 + 展示最高 Q + 刷新改推 .top

**Files:**
- Modify: `lib/features/results/results_page.dart`

**Interfaces:**
- Consumes: `ResultRow.quality`（Task 6）、`subProvider.notifier.pushFile`（Task 7 已校验 `.top`）、`cfg.subLatencyOutputFile`。
- Produces: 固定推 `cfg.subLatencyOutputFile`；候选文件仅 `subOutputFile`/`subLatencyOutputFile`；新增「最高质量分」统计卡。

- [ ] **Step 1: 修改候选文件列表与刷新按钮**

  - 候选列表（第 30-34 行）改为：

```dart
    final candidates = <String>[
      cfgAsync.value?.subOutputFile ?? 'addressesapi.txt',
      cfgAsync.value?.subLatencyOutputFile ?? 'addressesapi_top.txt',
    ].where((p) => p.isNotEmpty).toSet().where((p) => File(p).existsSync()).toList();
```

  - 刷新按钮（第 73-85 行）改为刷 `subLatencyOutputFile`：

```dart
                      IconButton.filledTonal(
                        icon: const Icon(Icons.refresh),
                        tooltip: '刷新',
                        onPressed: () async {
                          final cfg = await cfgAsync.value;
                          if (cfg != null) {
                            _selectedFile = cfg.subLatencyOutputFile;
                            _rawView = false;
                            setState(() {});
                            await ref.read(resultProvider.notifier).loadFile(cfg.subLatencyOutputFile);
                          }
                        },
                      ),
```

- [ ] **Step 2: 推送按钮固定推 subLatencyOutputFile**

  将 `_pushGithubButton(context, effectiveSelected)` 调用改为 `_pushGithubButton(context, cfgAsync.value?.subLatencyOutputFile ?? 'addressesapi_top.txt')`，并在方法内 label 改为 `Text(_pushing ? '推送中…' : '推送 GitHub')`（去掉文件名，因为固定）。

- [ ] **Step 3: 新增最高质量分统计**

  在 `_ResultsPageState` 加 `_bestQuality`：

```dart
  double? _bestQuality(List<ResultRow> rows) {
    double? best;
    for (final r in rows) {
      if (r.quality == null) continue;
      if (best == null || r.quality! > best) best = r.quality;
    }
    return best;
  }
```

  在 stats Wrap（第 167-178 行）追加一项：

```dart
                        _stat(context, '最高质量分',
                            bestQuality != null ? bestQuality.toStringAsFixed(2) : '—', Icons.star),
```

  并在 `build` 中 `final bestQuality = _bestQuality(rows);`（紧挨 `bestSpeed`/`lowestLatency` 定义后）。

- [ ] **Step 4: 修复 await_only_futures**

  第 77 行 `final cfg = await cfgAsync.value;` 改为 `final cfg = cfgAsync.value;`（删 `await`）。

- [ ] **Step 5: 运行 analyze + 测试**

Run: `cd D:\env\cfnb_app && flutter analyze lib/features/results/results_page.dart 2>&1 | Select-Object -First 15`
Expected: 无 error/warning。

- [ ] **Step 6: Commit**

```bash
cd D:\env\cfnb_app && git add lib/features/results/results_page.dart && git commit -q -m "fix(results): push .top only, show best quality, refresh top file"
```

---

### Task 9: settings_fields 删除死字段分组 + 清理 settings_page 无用方法

**Files:**
- Modify: `lib/features/settings/settings_fields.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `test/features/settings_results_test.dart`（确认字段引用已更新）

**Interfaces:**
- Consumes: 精简 AppConfig（Task 1）。
- Produces: `settingsFields` 仅含：订阅转换、延迟优选、带宽测速、GitHub 推送、外观。

- [ ] **Step 1: 重写 settingsFields 列表**

替换 `lib/features/settings/settings_fields.dart` 的 `settingsFields` 常量为：

```dart
const List<SettingField> settingsFields = [
  // 1. 订阅转换
  SettingField('1. 订阅转换', '主流程自动', 'SUB_CONVERT_ENABLED', 'bool'),
  SettingField('1. 订阅转换', '输入模式', 'SUB_INPUT_MODE', 'choice', ['both', 'node', 'url']),
  SettingField('1. 订阅转换', '候选订阅器', 'SUB_GENERATORS', 'list_str'),
  SettingField('1. 订阅转换', '节点域名', 'SUB_NODE_HOST', 'string'),
  SettingField('1. 订阅转换', '节点UUID', 'SUB_NODE_UUID', 'string'),
  SettingField('1. 订阅转换', '订阅链接', 'SUB_URLS', 'list_str'),
  SettingField('1. 订阅转换', '输出文件', 'SUB_OUTPUT_FILE', 'string'),
  SettingField('1. 订阅转换', '默认国家', 'SUB_DEFAULT_COUNTRY', 'string'),
  SettingField('1. 订阅转换', '域名解析IP', 'SUB_RESOLVE_DOMAIN', 'bool'),

  // 2. 延迟优选
  SettingField('2. 延迟优选', '延迟低于(ms)', 'SUB_LATENCY_MAX_MS', 'int', [10, 1000, 1]),
  SettingField('2. 延迟优选', '探测次数', 'SUB_LATENCY_PROBES', 'int', [1, 10, 1]),
  SettingField('2. 延迟优选', '输出文件', 'SUB_LATENCY_OUTPUT_FILE', 'string'),
  SettingField('2. 延迟优选', '连接超时(秒)', 'SUB_LATENCY_TIMEOUT', 'float', [0.1, 30.0, 0.1]),
  SettingField('2. 延迟优选', '并发数', 'SUB_LATENCY_WORKERS', 'int', [1, 1000, 1]),
  SettingField('2. 延迟优选', 'SNI', 'SUB_LATENCY_SNI', 'string'),
  SettingField('2. 延迟优选', '质量延迟权重', 'SUB_QUALITY_LATENCY_WEIGHT', 'float', [0.0, 1.0, 0.05]),

  // 3. 带宽测速
  SettingField('3. 带宽测速', '启用', 'SUB_SPEED_ENABLED', 'bool'),
  SettingField('3. 带宽测速', '仅测延迟≤(ms)', 'SUB_SPEED_LATENCY_LIMIT', 'int', [50, 500, 1]),
  SettingField('3. 带宽测速', '超时(秒)', 'SUB_SPEED_TIMEOUT', 'float', [1, 60, 1]),
  SettingField('3. 带宽测速', '并发', 'SUB_SPEED_WORKERS', 'int', [1, 100, 1]),
  SettingField('3. 带宽测速', '下载(MB)', 'SUB_SPEED_SIZE_MB', 'float', [0.1, 10, 0.1]),

  // 4. GitHub 推送
  SettingField('4. GitHub 推送', '仓库', 'GITHUB_REPO', 'string'),
  SettingField('4. GitHub 推送', '分支', 'GITHUB_BRANCH', 'string'),

  // 5. 外观
  SettingField('5. 外观', '主题', 'GUI_THEME', 'choice', ['light', 'dark']),
];
```

- [ ] **Step 2: 删除 settings_page 无用方法**

  删除 `_slider`/`_doubleSlider`/`_textList`（第 89-173 行，均未使用，analyze 已 warning）。保留 `_switch`/`_text`。

- [ ] **Step 3: 运行 analyze + 测试**

Run: `cd D:\env\cfnb_app && flutter analyze lib/features/settings 2>&1 | Select-Object -First 15`
Run: `cd D:\env\cfnb_app && flutter test test/features/settings_results_test.dart 2>&1 | Select-Object -First 15`
Expected: analyze 无 warning；测试 PASS。

- [ ] **Step 4: Commit**

```bash
cd D:\env\cfnb_app && git add lib/features/settings/settings_fields.dart lib/features/settings/settings_page.dart && git commit -q -m "refactor(settings): drop dead field groups, remove unused methods"
```

---

### Task 10: 全量 analyze + 测试清理收尾

**Files:**
- Modify: `lib/core/speed/speed_prober.dart`（删 `dart:typed_data` unused import）
- Modify: `lib/features/subscriptions/subscriptions_state.dart`（删未用 `app_logger` import，修 `_` 下划线）
- Modify: `lib/core/fetch/node_parser.dart`（for 循环加花括号，如第 145 行）
- Modify: `lib/features/settings/settings_page.dart`（第 23 行 for 加花括号）
- Modify: `lib/features/widgets/source_editor.dart`（第 21 行 for 加花括号）

**Interfaces:**
- 无新接口；收尾现有 23 个 analyze issue。

- [ ] **Step 1: 修复各文件 lint**

  - `speed_prober.dart` 第 3 行删 `import 'dart:typed_data';`
  - `subscriptions_state.dart` 第 12 行删 `import '../../core/logging/app_logger.dart';`；第 150 行 `(client) { client.badCertificateCallback = (_, __, ___) => true;` 改为 `(_, _, _) => true;`（若仍保留旧 proxy 代码已被 Task 7 删，则忽略）。
  - `node_parser.dart` 第 145 行 `for (...) stmt;` 改为 `for (...) { stmt; }`（按 analyze 提示定位）。
  - `settings_page.dart` 第 23 行 `for (final c in _ctl.values) c.dispose();` → `{ c.dispose(); }`。
  - `source_editor.dart` 第 21 行类似加花括号。

- [ ] **Step 2: 运行全量 analyze**

Run: `cd D:\env\cfnb_app && flutter analyze 2>&1 | Select-Object -First 30`
Expected: `0 issues found.`（或仅剩无法消除的 info，无 error/warning）。

- [ ] **Step 3: 运行全量测试**

Run: `cd D:\env\cfnb_app && flutter test 2>&1 | Select-Object -First 30`
Expected: 全部 PASS。

- [ ] **Step 4: Commit**

```bash
cd D:\env\cfnb_app && git add -A && git commit -q -m "chore: resolve analyze lint, finalize defect fixes"
```

---

## 自检（Spec 覆盖核对）

- A1 国家列 → Task 3（`nodeCountry` 已对）+ Task 6（`ResultRow.country` 改用 `nodeCountry`）。
- A2 裸 TCP → 全局约束，未接入 TLS（满足）。
- A3 v4 uuid → Task 1 默认值。
- A4 单 Dio → Task 7（`GithubPush.directDio()` 复用 + `createHttpClient`）。
- A5 ip.txt 移除 → Task 1（删 `outputFile`）+ Task 8（候选/刷新去 ip.txt）。
- B6 maxKeep → Task 4。
- B7 subLatencyProbes → Task 1（字段）+ Task 7（透传）。
- B8 并发 fetch → Task 5。
- B9 逐 URL 日志 → Task 5（保留 `_safeFetch` 记录）+ 确认。
- B10 最高 Q → Task 6（解析）+ Task 8（展示）。
- B11/B12 仅推 .top → Task 7（`isPushable` + `pushFile` 校验）+ Task 8（按钮固定推）。
- B13 subConvertEnabled 默认 true → Task 1。
- B14 subDefaultCountry 默认 '' → Task 1 + Task 3（空不写 #）。
- C15 死字段删干净 → Task 1（AppConfig）+ Task 2（repo）+ Task 9（settings UI）+ Task 3/8 引用清理。
- C16 硬编码本地路径 → Task 1（`defaultAdditionalSources` 删该行）。
- analyze 23 issue → Task 10。
- 测试策略 → 各 task 内含测试；Task 10 全绿。

全部覆盖，无遗漏。
