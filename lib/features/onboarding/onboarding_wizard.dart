import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/config_repository.dart';

/// 首次启动引导向导：PageView + 圆点指示器，四步完成基础配置。
class OnboardingWizard extends ConsumerStatefulWidget {
  final ConfigRepository repo;
  const OnboardingWizard({super.key, required this.repo});

  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  static const _totalPages = 4;

  // ---- Step 2 本地状态 ----
  String _subInputMode = 'both';
  List<String> _generators = [];
  Set<String> _disabledGenerators = {};
  final _urlTextCtl = TextEditingController();

  // ---- Step 3 本地状态 ----
  final _tokenCtl = TextEditingController();
  final _repoCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cfg = widget.repo.current;
    _subInputMode = cfg.subInputMode;
    _generators = List.of(cfg.subGenerators);
    _disabledGenerators = Set.of(cfg.subDisabledGenerators);
    _urlTextCtl.text = cfg.subUrls.join('\n');
    _tokenCtl.text = cfg.githubToken;
    _repoCtl.text = cfg.githubRepo;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _urlTextCtl.dispose();
    _tokenCtl.dispose();
    _repoCtl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageCtrl.nextPage(duration: Motion.durBase, curve: Motion.curveStandard);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageCtrl.previousPage(duration: Motion.durBase, curve: Motion.curveStandard);
    }
  }

  Future<void> _complete() async {
    // 解析 URL 文本为列表
    final urls = _urlTextCtl.text
        .split(RegExp(r'[\n,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final updated = widget.repo.current.copyWith(
      subInputMode: _subInputMode,
      subGenerators: _generators,
      subDisabledGenerators: _disabledGenerators,
      subUrls: urls,
      githubToken: _tokenCtl.text.trim(),
      githubRepo: _repoCtl.text.trim(),
      hasCompletedOnboarding: true,
    );

    await widget.repo.save(updated);
    ref.invalidate(configProvider);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 600;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ---- 页面内容 ----
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildStep1Welcome(t, isWide),
                  _buildStep2InputMode(t, isWide),
                  _buildStep3Github(t, isWide),
                  _buildStep4Completion(t, isWide),
                ],
              ),
            ),
            // ---- 圆点指示器 ----
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _buildDots(t),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  //  Step 1: Welcome
  // =========================================================================
  Widget _buildStep1Welcome(AppThemeExt t, bool isWide) {
    return _stepContainer(
      isWide: isWide,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.edgeOrange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.cloud_outlined, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            'CF优选工具',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: t.text),
          ),
          const SizedBox(height: 16),
          Text(
            '自动抓取订阅节点\n检测 IP 落地地区 → 推送 GitHub',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: t.textDim, height: 1.6),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: 200,
            height: 48,
            child: FilledButton(
              onPressed: _nextPage,
              child: const Text('开始配置', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  //  Step 2: Subscription Input Mode
  // =========================================================================
  Widget _buildStep2InputMode(AppThemeExt t, bool isWide) {
    final showGenerators = _subInputMode == 'node' || _subInputMode == 'both';
    final showUrls = _subInputMode == 'url' || _subInputMode == 'both';

    return _stepContainer(
      isWide: isWide,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepTitle('订阅输入模式', t),
            const SizedBox(height: 20),
            // Radio group
            ..._radioOption('node', '仅订阅器', '使用内置订阅器生成节点', t),
            ..._radioOption('url', '仅订阅 URL', '直接粘贴订阅链接', t),
            ..._radioOption('both', '两者都用', '同时使用订阅器和订阅链接', t),
            const SizedBox(height: 20),

            // Generators section
            if (showGenerators) ...[
              _sectionLabel('订阅器列表', t),
              const SizedBox(height: 8),
              for (var i = 0; i < _generators.length; i++)
                _buildGeneratorRow(i, t),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加订阅器'),
                onPressed: () => setState(() {
                  _generators.add('名称|域名');
                }),
              ),
              const SizedBox(height: 20),
            ],

            // URL input section
            if (showUrls) ...[
              _sectionLabel('订阅链接（每行一个）', t),
              const SizedBox(height: 8),
              TextField(
                controller: _urlTextCtl,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://example.com/sub\nhttps://another.com/sub',
                  hintStyle: TextStyle(color: t.textDim, fontSize: 12),
                  filled: true,
                  fillColor: t.surface,
                  border: OutlineInputBorder(
                    borderRadius: t.radius,
                    borderSide: BorderSide(color: t.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: t.radius,
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: t.radius,
                    borderSide: BorderSide(color: AppTheme.edgeOrange, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],

            const SizedBox(height: 32),
            _buildNavButtons(showBack: true, onNext: _nextPage),
          ],
        ),
      ),
    );
  }

  List<Widget> _radioOption(String value, String title, String subtitle, AppThemeExt t) {
    return [
      InkWell(
        borderRadius: t.radius,
        onTap: () => setState(() => _subInputMode = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Radio<String>(
                value: value,
                groupValue: _subInputMode,
                onChanged: (v) => setState(() => _subInputMode = v!),
                activeColor: AppTheme.edgeOrange,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: t.textDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildGeneratorRow(int index, AppThemeExt t) {
    final entry = _generators[index];
    final name = entry.split('|').first.trim();
    final isDisabled = _disabledGenerators.contains(name);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry,
              style: TextStyle(
                fontFamily: 'AppMono',
                fontSize: 13,
                color: isDisabled ? t.textDim : t.text,
                decoration: isDisabled ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          IconButton(
            tooltip: isDisabled ? '启用' : '禁用',
            icon: Icon(
              isDisabled ? Icons.toggle_off : Icons.toggle_on,
              color: isDisabled ? null : AppTheme.edgeOrange,
              size: 28,
            ),
            onPressed: () => setState(() {
              final set = {..._disabledGenerators};
              if (set.contains(name)) {
                set.remove(name);
              } else {
                set.add(name);
              }
              _disabledGenerators = set;
            }),
          ),
          IconButton(
            tooltip: '删除',
            icon: Icon(Icons.delete_outline, color: t.danger, size: 20),
            onPressed: () => setState(() => _generators.removeAt(index)),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  //  Step 3: GitHub (Optional)
  // =========================================================================
  Widget _buildStep3Github(AppThemeExt t, bool isWide) {
    return _stepContainer(
      isWide: isWide,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepTitle('GitHub 推送（可选）', t),
            const SizedBox(height: 8),
            Text(
              '将优选结果推送到 GitHub 仓库，可稍后在配置页设置。',
              style: TextStyle(fontSize: 13, color: t.textDim),
            ),
            const SizedBox(height: 24),

            _sectionLabel('Personal Access Token', t),
            const SizedBox(height: 4),
            TextField(
              controller: _tokenCtl,
              obscureText: true,
              style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'ghp_xxxxxxxxxxxx',
                hintStyle: TextStyle(color: t.textDim, fontSize: 12),
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                  borderRadius: t.radius,
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: t.radius,
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: t.radius,
                  borderSide: BorderSide(color: AppTheme.edgeOrange, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '前往 GitHub Settings → Developer settings → Personal access tokens',
              style: TextStyle(fontSize: 11, color: AppTheme.edgeOrange, decoration: TextDecoration.underline),
            ),
            const SizedBox(height: 20),

            _sectionLabel('仓库（owner/repo 格式）', t),
            const SizedBox(height: 4),
            TextField(
              controller: _repoCtl,
              style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Hoffnungsschimmers/mnscn',
                hintStyle: TextStyle(color: t.textDim, fontSize: 12),
                filled: true,
                fillColor: t.surface,
                border: OutlineInputBorder(
                  borderRadius: t.radius,
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: t.radius,
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: t.radius,
                  borderSide: BorderSide(color: AppTheme.edgeOrange, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _complete,
                    child: const Text('跳过'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _complete,
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Back button
            Center(
              child: TextButton(
                onPressed: _prevPage,
                child: Text('返回', style: TextStyle(color: t.textDim)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  //  Step 4: Completion
  // =========================================================================
  Widget _buildStep4Completion(AppThemeExt t, bool isWide) {
    return _stepContainer(
      isWide: isWide,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: t.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_outline, color: t.success, size: 48),
          ),
          const SizedBox(height: 24),
          Text(
            '配置完成！',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: t.text),
          ),
          const SizedBox(height: 12),
          Text(
            '点击「运行」标签开始使用',
            style: TextStyle(fontSize: 15, color: t.textDim),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: 200,
            height: 48,
            child: FilledButton(
              onPressed: _complete,
              child: const Text('开始使用', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  //  Shared widgets
  // =========================================================================

  /// 响应式内容容器：窄屏全宽 padding，宽屏居中限宽。
  Widget _stepContainer({required bool isWide, required Widget child}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 520 : double.infinity),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 24, vertical: 24),
          child: child,
        ),
      ),
    );
  }

  Widget _stepTitle(String text, AppThemeExt t) {
    return Text(
      text,
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: t.text),
    );
  }

  Widget _sectionLabel(String text, AppThemeExt t) {
    return Text(
      text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text),
    );
  }

  Widget _buildDots(AppThemeExt t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalPages, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: Motion.durFast,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.edgeOrange : t.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildNavButtons({required bool showBack, required VoidCallback onNext}) {
    return Row(
      children: [
        if (showBack)
          Expanded(
            child: OutlinedButton(
              onPressed: _prevPage,
              child: const Text('返回'),
            ),
          ),
        if (showBack) const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            onPressed: onNext,
            child: const Text('下一步'),
          ),
        ),
      ],
    );
  }
}
