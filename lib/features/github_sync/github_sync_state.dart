import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_push.dart';
import '../results/result_state.dart';

// ═══════════════════════════════════════════════════════
// GitHub 同步状态
// ═══════════════════════════════════════════════════════

class GithubSyncState {
  /// 远程文件解析出的节点列表（可编辑）。
  final List<ResultRow> remoteNodes;

  /// 远程文件 SHA（推送时用于 GitHub API 更新）。
  final String? remoteSha;

  /// 远程文件的 GitHub 路径（如 addressesapi_top.txt）。
  final String? remoteFile;

  /// 远程文件最近一次提交时间（ISO 8601），来自 GitHub commits API。
  final String? remoteUpdatedAt;

  /// 是否正在拉取。
  final bool loading;

  /// 是否正在推送。
  final bool pushing;

  /// 错误信息（null 表示无错误）。
  final String? error;

  /// 上次操作的消息（成功/失败）。
  final String? message;

  /// 搜索关键词（用于过滤节点）。
  final String searchQuery;

  /// 过滤后的节点列表（根据 searchQuery 筛选）。
  List<ResultRow> get filteredRemoteNodes {
    var result = remoteNodes;
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((r) =>
              r.ipPort.toLowerCase().contains(q) ||
              r.annotation.toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  const GithubSyncState({
    this.remoteNodes = const [],
    this.remoteSha,
    this.remoteFile,
    this.loading = false,
    this.pushing = false,
    this.error,
    this.message,
    this.searchQuery = '',
    this.remoteUpdatedAt,
  });

  GithubSyncState copyWith({
    List<ResultRow>? remoteNodes,
    String? remoteSha,
    bool clearSha = false,
    String? remoteFile,
    bool clearFile = false,
    bool? loading,
    bool? pushing,
    String? error,
    bool clearError = false,
    String? message,
    bool clearMessage = false,
    String? searchQuery,
    String? remoteUpdatedAt,
    bool clearUpdatedAt = false,
  }) =>
      GithubSyncState(
        remoteNodes: remoteNodes ?? this.remoteNodes,
        remoteSha: clearSha ? null : (remoteSha ?? this.remoteSha),
        remoteFile: clearFile ? null : (remoteFile ?? this.remoteFile),
        loading: loading ?? this.loading,
        pushing: pushing ?? this.pushing,
        error: clearError ? null : (error ?? this.error),
        message: clearMessage ? null : (message ?? this.message),
        searchQuery: searchQuery ?? this.searchQuery,
        remoteUpdatedAt: clearUpdatedAt ? null : (remoteUpdatedAt ?? this.remoteUpdatedAt),
      );
}

// ═══════════════════════════════════════════════════════
// GithubSyncNotifier
// ═══════════════════════════════════════════════════════

class GithubSyncNotifier extends StateNotifier<GithubSyncState> {
  final Ref ref;

  /// 可注入的 GithubPush 工厂（测试用），null 时按配置构造。
  final GithubPush Function(AppConfig config)? githubFactory;

  GithubSyncNotifier(this.ref, {this.githubFactory})
      : super(const GithubSyncState());

  Future<AppConfig> _cfg() async =>
      await ref.read(configRepositoryProvider.future).then((r) => r.current);

  GithubPush? _github(AppConfig cfg) {
    if (githubFactory != null) return githubFactory!(cfg);
    if (cfg.githubToken.isEmpty) return null;
    return GithubPush(
      token: cfg.githubToken,
      repo: cfg.githubRepo,
      branch: cfg.githubBranch,
    );
  }

  /// 从 GitHub 拉取远程结果文件并解析为节点列表。
  Future<void> pullFromGithub() async {
    state = state.copyWith(loading: true, clearError: true, clearMessage: true);
    try {
      final cfg = await _cfg();
      final github = _github(cfg);
      if (github == null) {
        state = state.copyWith(
          loading: false,
          error: 'GitHub 未配置（请在设置填写 Token/Repo/Branch）',
        );
        return;
      }
      final file = cfg.landingOutputFile;
      final (content, sha) = await github.pullFile(file);
      if (content == null) {
        state = state.copyWith(
          loading: false,
          error: '远程文件不存在：$file',
          remoteFile: file,
          clearSha: true,
          clearUpdatedAt: true,
        );
        return;
      }
      final rows = parseResultLines(content);
      // 获取该文件最近一次提交时间（失败不阻塞，仅提示未知）
      String? updatedAt;
      try {
        updatedAt = await github.fetchCommitTime(file);
      } catch (_) {}
      state = state.copyWith(
        loading: false,
        remoteNodes: rows,
        remoteSha: sha,
        remoteFile: file,
        remoteUpdatedAt: updatedAt,
        message: '拉取成功：$file（${rows.length} 个节点）',
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: '拉取失败：$e',
      );
    }
  }

  /// 删除远程节点列表中指定索引的节点。
  void removeRemoteNode(int index) {
    final nodes = [...state.remoteNodes];
    if (index >= 0 && index < nodes.length) {
      nodes.removeAt(index);
      state = state.copyWith(remoteNodes: nodes);
    }
  }

  /// 更新远程节点列表中指定索引的节点。[latency] 为空时保留原延迟。
  void updateRemoteNode(int index, String rawLine, {String? latency}) {
    final line = rawLine.trim();
    if (line.isEmpty || !line.contains(':')) return;
    if (index < 0 || index >= state.remoteNodes.length) return;
    final nodes = [...state.remoteNodes];
    final effectiveLatency = (latency != null && latency.isNotEmpty)
        ? latency
        : state.remoteNodes[index].latency;
    nodes[index] = ResultRow(line, effectiveLatency);
    state = state.copyWith(remoteNodes: nodes);
  }

  /// 从原始文本批量设置节点（用于粘贴大量 IP 场景，覆盖替换）。
  void setNodesFromText(String text) {
    final rows = parseResultLines(text);
    state = state.copyWith(
      remoteNodes: rows,
      message: '已解析 ${rows.length} 个节点',
    );
  }

  /// 追加文本中的节点到现有列表，然后按 ip:port 去重（新数据优先）。
  void appendAndDedup(String text) {
    final newRows = parseResultLines(text);
    if (newRows.isEmpty) {
      state = state.copyWith(message: '未解析到有效节点');
      return;
    }
    final combined = [...state.remoteNodes, ...newRows];
    // 去重：后出现的覆盖先出现的（新追加的在后面，优先保留）
    final latest = <String, ResultRow>{};
    for (final r in combined) {
      latest[r.ipPort] = r;
    }
    final deduped = latest.values.toList();
    final added = newRows.length;
    final removed = combined.length - deduped.length;
    state = state.copyWith(
      remoteNodes: deduped,
      message: '追加 $added 个节点${removed > 0 ? '，去重 $removed 个' : ''}（共 ${deduped.length} 个）',
    );
  }

  /// 按 ip:port 去重。相同 IP 和端口视为同一节点，保留后加入的（新数据优先）。
  void deduplicateNodes() {
    final latest = <String, ResultRow>{};
    for (final r in state.remoteNodes) {
      latest[r.ipPort] = r; // 后出现的覆盖先出现的
    }
    final deduped = latest.values.toList();
    final removed = state.remoteNodes.length - deduped.length;
    state = state.copyWith(
      remoteNodes: deduped,
      message: removed > 0
          ? '去重完成：移除 $removed 个重复节点（${deduped.length} 个唯一）'
          : '无重复节点（${deduped.length} 个）',
    );
  }

  /// 追加新节点到远程列表末尾。
  void addRemoteNode(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty || !line.contains(':')) return;
    final nodes = [...state.remoteNodes, ResultRow(line)];
    state = state.copyWith(remoteNodes: nodes);
  }

  /// 将当前远程节点列表推送到 GitHub。
  ///
  /// 内置 SHA 冲突自动重试（[GithubPush.pushFile] 默认 2 次），
  /// 遇到 422 会自动重新拉取 SHA 并重试，无需用户干预。
  Future<void> pushToGithub() async {
    state = state.copyWith(pushing: true, clearError: true, clearMessage: true);
    try {
      final cfg = await _cfg();
      final github = _github(cfg);
      if (github == null) {
        state = state.copyWith(
          pushing: false,
          error: 'GitHub 未配置（请在设置填写 Token/Repo/Branch）',
        );
        return;
      }
      final file = state.remoteFile ?? cfg.landingOutputFile;

      // 序列化节点列表为文本
      final sb = StringBuffer();
      for (final r in state.remoteNodes) {
        final parts = <String>[r.node];
        if (r.latency != null) parts.add(r.latency!);
        sb.writeln(parts.join(' '));
      }
      final content = sb.toString();

      // pushFile 内置 SHA 冲突自动重试
      final fileName = file.contains('/') || file.contains('\\')
          ? file.split(RegExp(r'[/\\]')).last
          : file;
      final code = await github.pushFile(file, content,
          message: 'sync $fileName (${state.remoteNodes.length} nodes)');

      // 推送后重新拉取获取新 sha。刷新失败不影响推送结果：
      // 不误报"推送失败"，仅记警告日志，sha 下次拉取时自动更新。
      var newSha = state.remoteSha;
      try {
        final (_, sha) = await github.pullFile(file);
        newSha = sha;
      } catch (e) {
        ref.read(subLoggerProvider).warning('推送成功但刷新远程 SHA 失败：$e');
      }

      state = state.copyWith(
        pushing: false,
        remoteSha: newSha,
        message: '推送成功：$file（${state.remoteNodes.length} 个节点，HTTP $code）',
      );
    } catch (e) {
      state = state.copyWith(
        pushing: false,
        error: '推送失败：$e',
      );
    }
  }

  /// 清空状态。
  void reset() {
    state = const GithubSyncState();
  }

  /// 设置搜索关键词。
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final githubSyncProvider =
    StateNotifierProvider<GithubSyncNotifier, GithubSyncState>(
        (ref) => GithubSyncNotifier(ref));
