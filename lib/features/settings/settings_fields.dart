/// 设置字段声明（数据驱动渲染，对应旧版 gui/constants.py 的 SETTINGS_FIELDS）。
///
/// 类型：bool / int / float / string / list_int / list_str / choice /
///       sources（节点源多行 URL）/ multiline（多行文本）。
/// opts：int/float 为 (min,max,step)；choice 为可选值列表；其余为 null。
class SettingField {
  final String category;
  final String label;
  final String key;
  final String type;
  final List<dynamic>? opts;
  const SettingField(this.category, this.label, this.key, this.type, [this.opts]);
}

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
  SettingField('1. 订阅转换', '抓取超时(秒)', 'SUB_FETCH_TIMEOUT', 'int', [1, 60, 1]),
  SettingField('1. 订阅转换', '连接超时(秒)', 'SUB_FETCH_CONNECT_TIMEOUT', 'int', [1, 30, 1]),
  SettingField('1. 订阅转换', '失败重试次数', 'SUB_FETCH_MAX_RETRIES', 'int', [0, 10, 1]),
  SettingField('1. 订阅转换', '重试间隔(秒)', 'SUB_FETCH_RETRY_DELAY', 'int', [0, 60, 1]),
  SettingField('1. 订阅转换', '域名解析并发', 'SUB_RESOLVE_WORKERS', 'int', [1, 256, 1]),

  // 2. 延迟优选
  SettingField('2. 延迟优选', '延迟低于(ms)', 'SUB_LATENCY_MAX_MS', 'int', [10, 1000, 1]),
  SettingField('2. 延迟优选', '保留前N名(按质量)', 'SUB_LATENCY_TOP_N', 'int', [0, 500, 1]),
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
  SettingField('3. 带宽测速', '每节点测速次数', 'SUB_SPEED_PROBES', 'int', [1, 5, 1]),
  SettingField('3. 带宽测速', '带宽参考值(Mbps)', 'SUB_BANDWIDTH_REF_MBPS', 'float', [5, 100, 1]),

  // 4. GitHub 推送
  SettingField('4. GitHub 推送', 'Token', 'GITHUB_TOKEN', 'string'),
  SettingField('4. GitHub 推送', '仓库', 'GITHUB_REPO', 'string'),
  SettingField('4. GitHub 推送', '分支', 'GITHUB_BRANCH', 'string'),

  // 5. 外观
  SettingField('5. 外观', '主题', 'GUI_THEME', 'choice', ['light', 'dark']),
];

/// 把草稿 JSON 中的特殊字段（sources）转换为 AppConfig 能识别的结构。
Map<String, dynamic> normalizeDraft(Map<String, dynamic> draft) {
  final out = <String, dynamic>{...draft};
  // SUB_GENERATORS / SUB_URLS / ALLOWED_COUNTRIES 等为 list_str，保持 list
  // ADDITIONAL_SOURCES 在 UI 中以多行文本编辑，保存时转回 [{url,enabled}]
  if (out['ADDITIONAL_SOURCES'] is String) {
    final lines = (out['ADDITIONAL_SOURCES'] as String)
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => {'url': e, 'enabled': true})
        .toList();
    out['ADDITIONAL_SOURCES'] = lines;
  }
  return out;
}
