/// 应用配置模型（仅保留「订阅转换 → 落地检测 → 推送 GitHub」三步流程所需字段）。
///
/// 普通 Dart class + 手写 fromJson/toJson，避免 codegen 复杂度。所有字段带默认值，
/// 等价于旧版 Python config.Config 的 pydantic Field(default=...)。SharedPreferences
/// 中的旧键（CF DNS / WxPusher / ASN / 可用性 / 广告 / 旧筛选等）读时忽略，向后兼容。
class AppConfig {
  // ============ 订阅转换 ============
  final String subInputMode;
  final List<String> subUrls;
  final Set<String> subDisabledUrls;
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
  final double subFetchRetryDelay;

  // ============ 落地检测与输出 ============
  final String landingOutputFile; // 最终结果文件（落地检测写回 + 推送目标，默认 addressesapi_top.txt）
  final bool subInsecure; // 跳过订阅抓取时的 TLS 证书校验（默认 false，安全默认）

  // ============ GitHub 推送（独立的优选结果仓） ============
  final String githubToken;
  final String githubRepo;
  final String githubBranch;

  // ============ 自动更新 ============
  final bool subAutoUpdateEnabled;    // 是否启用自动更新
  final int subAutoUpdateIntervalMin; // 自动更新间隔（分钟），默认 60

  // ============ Webhook 通知 ============
  final String webhookUrl;        // Webhook URL (Telegram/Discord)
  final String webhookType;       // 'telegram' | 'discord' | 'none'
  final bool webhookOnComplete;   // 任务完成时通知
  final bool webhookOnError;      // 任务失败时通知

  // ============ WebDAV 同步（云盘备份/恢复） ============
  final String webdavUrl;        // WebDAV 服务器地址（如 https://dav.jianguoyun.com/dav）
  final String webdavUser;       // 账号
  final String webdavPassword;   // 密码（敏感，经 SecureKV 存储）
  final bool webdavAutoSync;     // 自动同步开关（开启后按间隔定时推送备份）
  final int webdavAutoSyncIntervalMin; // 自动同步间隔（分钟）

  // ============ 外观 ============
  final String guiTheme;

  // ============ 引导 ============
  final bool hasCompletedOnboarding;

  const AppConfig({
    this.subInputMode = 'both',
    this.subUrls = const [],
    this.subDisabledUrls = const {},
    this.subNodeHost = 'example.com',
    this.subNodeUuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx',
    this.subGenerators = defaultSubGenerators,
    this.subDisabledGenerators = const {},
    this.subOutputFile = 'addressesapi.txt',
    this.subDefaultCountry = '',
    this.subResolveDomain = true,
    this.subFetchTimeout = 20,
    this.subFetchConnectTimeout = 10,
    this.subFetchMaxRetries = 2,
    this.subFetchRetryDelay = 2.0,
    this.landingOutputFile = 'addressesapi_top.txt',
    this.subInsecure = false,
    this.githubToken = '',
    this.githubRepo = 'Hoffnungsschimmers/mnscn',
    this.githubBranch = 'main',
    this.subAutoUpdateEnabled = false,
    this.subAutoUpdateIntervalMin = 60,
    this.webhookUrl = '',
    this.webhookType = 'none',
    this.webhookOnComplete = true,
    this.webhookOnError = true,
    this.webdavUrl = '',
    this.webdavUser = '',
    this.webdavPassword = '',
    this.webdavAutoSync = false,
    this.webdavAutoSyncIntervalMin = 30,
    this.guiTheme = 'light',
    this.hasCompletedOnboarding = false,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    T pick<T>(String key, T fallback) {
      final v = json[key];
      if (v is T) return v;
      // 兼容字符串→数字的类型强转（如 "50" → 50）
      if (T == int && v is num) return v.toInt() as T;
      if (T == double && v is num) return v.toDouble() as T;
      if (T == int && v is String) { final n = int.tryParse(v); if (n != null) return n as T; }
      if (T == double && v is String) { final n = double.tryParse(v); if (n != null) return n as T; }
      if (T == bool && v is String) { final b = v.toLowerCase(); if (b == 'true') return true as T; if (b == 'false') return false as T; }
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
    return AppConfig(
      subInputMode: pick('SUB_INPUT_MODE', 'both'),
      subUrls: pickStrList('SUB_URLS', const []),
      subDisabledUrls: pickStrSet('SUB_DISABLED_URLS', const {}),
      subNodeHost: pick('SUB_NODE_HOST', 'example.com'),
      subNodeUuid: pick('SUB_NODE_UUID', 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'),
      subGenerators: pickStrList('SUB_GENERATORS', defaultSubGenerators),
      subDisabledGenerators: pickStrSet('SUB_DISABLED_GENERATORS', const {}),
      subOutputFile: pick('SUB_OUTPUT_FILE', 'addressesapi.txt'),
      subDefaultCountry: pick('SUB_DEFAULT_COUNTRY', ''),
      subResolveDomain: pick('SUB_RESOLVE_DOMAIN', true),
      subFetchTimeout: pick('SUB_FETCH_TIMEOUT', 20),
      subFetchConnectTimeout: pick('SUB_FETCH_CONNECT_TIMEOUT', 10),
      subFetchMaxRetries: pick('SUB_FETCH_MAX_RETRIES', 2),
      subFetchRetryDelay: (pick('SUB_FETCH_RETRY_DELAY', 2.0) as num).toDouble(),
      subInsecure: pick('SUB_INSECURE', false),
      // 新键优先；旧键 SUB_LATENCY_OUTPUT_FILE 兜底（延迟优选已移除，兼容历史配置）。
      landingOutputFile: pick('LANDING_OUTPUT_FILE', pick('SUB_LATENCY_OUTPUT_FILE', 'addressesapi_top.txt')),
      githubToken: pick('GITHUB_TOKEN', ''),
      githubRepo: pick('GITHUB_REPO', 'Hoffnungsschimmers/mnscn'),
      githubBranch: pick('GITHUB_BRANCH', 'main'),
      subAutoUpdateEnabled: pick('SUB_AUTO_UPDATE_ENABLED', false),
      subAutoUpdateIntervalMin: pick('SUB_AUTO_UPDATE_INTERVAL_MIN', 60),
      webhookUrl: pick('WEBHOOK_URL', ''),
      webhookType: pick('WEBHOOK_TYPE', 'none'),
      webhookOnComplete: pick('WEBHOOK_ON_COMPLETE', true),
      webhookOnError: pick('WEBHOOK_ON_ERROR', true),
      webdavUrl: pick('WEBDAV_URL', ''),
      webdavUser: pick('WEBDAV_USER', ''),
      webdavPassword: pick('WEBDAV_PASSWORD', ''),
      webdavAutoSync: pick('WEBDAV_AUTO_SYNC', false),
      webdavAutoSyncIntervalMin: pick('WEBDAV_AUTO_SYNC_INTERVAL_MIN', 30),
      guiTheme: pick('GUI_THEME', 'light'),
      hasCompletedOnboarding: pick('HAS_COMPLETED_ONBOARDING', false),
    );
  }

  Map<String, dynamic> toJson() => {
        'SUB_INPUT_MODE': subInputMode,
        'SUB_URLS': subUrls,
        'SUB_DISABLED_URLS': subDisabledUrls.toList(),
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
        'SUB_INSECURE': subInsecure,
        'LANDING_OUTPUT_FILE': landingOutputFile,
        'GITHUB_REPO': githubRepo,
        'GITHUB_BRANCH': githubBranch,
        'SUB_AUTO_UPDATE_ENABLED': subAutoUpdateEnabled,
        'SUB_AUTO_UPDATE_INTERVAL_MIN': subAutoUpdateIntervalMin,
        'WEBHOOK_TYPE': webhookType,
        'WEBHOOK_ON_COMPLETE': webhookOnComplete,
        'WEBHOOK_ON_ERROR': webhookOnError,
        'WEBDAV_URL': webdavUrl,
        'WEBDAV_USER': webdavUser,
        'WEBDAV_AUTO_SYNC': webdavAutoSync,
        'WEBDAV_AUTO_SYNC_INTERVAL_MIN': webdavAutoSyncIntervalMin,
        'GUI_THEME': guiTheme,
        'HAS_COMPLETED_ONBOARDING': hasCompletedOnboarding,
      };

  AppConfig copyWith({
    String? subInputMode,
    List<String>? subUrls,
    Set<String>? subDisabledUrls,
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
    double? subFetchRetryDelay,
    String? landingOutputFile,
    bool? subInsecure,
    String? githubToken,
    String? githubRepo,
    String? githubBranch,
    bool? subAutoUpdateEnabled,
    int? subAutoUpdateIntervalMin,
    String? webhookUrl,
    String? webhookType,
    bool? webhookOnComplete,
    bool? webhookOnError,
    String? webdavUrl,
    String? webdavUser,
    String? webdavPassword,
    bool? webdavAutoSync,
    int? webdavAutoSyncIntervalMin,
    String? guiTheme,
    bool? hasCompletedOnboarding,
  }) {
    return AppConfig(
      subInputMode: subInputMode ?? this.subInputMode,
      subUrls: subUrls ?? this.subUrls,
      subDisabledUrls: subDisabledUrls ?? this.subDisabledUrls,
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
      landingOutputFile: landingOutputFile ?? this.landingOutputFile,
      subInsecure: subInsecure ?? this.subInsecure,
      githubToken: githubToken ?? this.githubToken,
      githubRepo: githubRepo ?? this.githubRepo,
      githubBranch: githubBranch ?? this.githubBranch,
      subAutoUpdateEnabled: subAutoUpdateEnabled ?? this.subAutoUpdateEnabled,
      subAutoUpdateIntervalMin: subAutoUpdateIntervalMin ?? this.subAutoUpdateIntervalMin,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      webhookType: webhookType ?? this.webhookType,
      webhookOnComplete: webhookOnComplete ?? this.webhookOnComplete,
      webhookOnError: webhookOnError ?? this.webhookOnError,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      webdavUser: webdavUser ?? this.webdavUser,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      webdavAutoSync: webdavAutoSync ?? this.webdavAutoSync,
      webdavAutoSyncIntervalMin:
          webdavAutoSyncIntervalMin ?? this.webdavAutoSyncIntervalMin,
      guiTheme: guiTheme ?? this.guiTheme,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }

  /// 校验配置合法性。返回错误字符串列表，为空表示通过。
  List<String> validate() {
    final errors = <String>[];
    if (!['node', 'url', 'both'].contains(subInputMode)) {
      errors.add("SUB_INPUT_MODE 必须是 'node'、'url' 或 'both'");
    }
    if (subFetchTimeout < 1) {
      errors.add('订阅抓取超时必须 ≥ 1 秒');
    }
    if (subAutoUpdateIntervalMin < 5) {
      errors.add('自动更新间隔必须 ≥ 5 分钟');
    }
    if (webhookType != 'none' && webhookUrl.isEmpty) {
      errors.add('已选择 Webhook 类型但 URL 为空');
    }
    if (webhookType != 'none' && !['telegram', 'discord'].contains(webhookType)) {
      errors.add("WEBHOOK_TYPE 必须是 'telegram'、'discord' 或 'none'");
    }
    if (webdavAutoSync && webdavUrl.isEmpty) {
      errors.add('开启自动同步但 WebDAV 地址为空');
    }
    if (webdavAutoSyncIntervalMin < 5) {
      errors.add('自动同步间隔必须 ≥ 5 分钟');
    }
    return errors;
  }
}

/// 把相对输出文件名解析为绝对路径：若已是绝对路径则原样返回，
/// 否则拼接 [baseDir]（运行时为 getApplicationDocumentsDirectory()）。
String resolveOutputPath(String name, String baseDir) {
  if (name.isEmpty) return name;
  final isAbs = name.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(name) ||
      name.startsWith(r'\\');
  return isAbs ? name : '$baseDir/$name'.replaceAll('\\', '/');
}

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
