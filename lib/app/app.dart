import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/github_sync/github_sync_tab.dart';
import '../features/results/results_tab.dart';
import '../features/results/result_state.dart';
import '../features/subscriptions/config_tab.dart';
import '../features/subscriptions/run_tab.dart';
import '../features/subscriptions/subscriptions_state.dart';
import '../features/webdav/webdav_sync_panel.dart';
import 'breakpoints.dart';
import 'motion.dart';
import 'providers.dart';
import 'shortcuts.dart';
import 'theme.dart';

final tabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final size = MediaQuery.sizeOf(context);
    final formFactor = formFactorOf(size.width);
    final t = AppThemeExt.of(context);

    // Action handlers（供快捷键触发）
    void switchTab(int i) => ref.read(tabProvider.notifier).state = i;
    void nextTab() => switchTab((ref.read(tabProvider) + 1) % 4);
    void prevTab() => switchTab((ref.read(tabProvider) - 1 + 4) % 4);
    Future<void> refreshResults() async {
      var cfg = ref.read(latestConfigProvider);
      if (cfg == null) {
        cfg = (await ref.read(configRepositoryProvider.future)).current;
      }
      if (!cfg.subOutputFile.isEmpty) {
        ref.read(resultProvider.notifier).refreshFile(cfg.subOutputFile);
      }
    }

    final appBar = AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: t.accentGradient(),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.cloud_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('CF优选',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        // WebDAV 同步入口：直接打开同步面板（同步配置 / 同步结果 二选一）
        IconButton(
          tooltip: 'WebDAV 同步',
          icon: const Icon(Icons.cloud_sync_outlined),
          onPressed: () => showWebDavSyncSheet(context, ref),
        ),
        IconButton(
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
          tooltip: Theme.of(context).brightness == Brightness.dark ? '切换浅色' : '切换深色',
          onPressed: () async {
            final current = ref.read(themeModeProvider);
            final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            ref.read(themeModeProvider.notifier).state = next;
            final repo = await ref.read(configRepositoryProvider.future);
            await repo.save(repo.current.copyWith(guiTheme: next == ThemeMode.dark ? 'dark' : 'light'));
          },
        ),
        const SizedBox(width: 8),
      ],
    );

    Widget body;
    Widget? bottomNav;
    Widget? sideRail;

    // ── 中型及以上（>=600dp）→ NavigationRail（桌面侧边栏）──
    if (formFactor != FormFactor.compact) {
      sideRail = NavigationRail(
        selectedIndex: tab,
        onDestinationSelected: switchTab,
        labelType: NavigationRailLabelType.all,
        destinations: const [
          NavigationRailDestination(icon: Icon(Icons.tune), label: Text('配置')),
          NavigationRailDestination(icon: Icon(Icons.play_arrow), label: Text('运行')),
          NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('结果')),
          NavigationRailDestination(icon: Icon(Icons.sync), label: Text('同步')),
        ],
      );
      body = Expanded(child: _TabStack(tab: tab));
    } else {
      // ── 紧凑（<600dp）→ 底部 NavigationBar（手机底边栏）──
      bottomNav = SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: switchTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.tune), label: '配置'),
            NavigationDestination(icon: Icon(Icons.play_arrow), label: '运行'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: '结果'),
            NavigationDestination(icon: Icon(Icons.sync), label: '同步'),
          ],
        ),
      );
      body = SafeArea(child: _TabStack(tab: tab));
    }

    return Actions(
      actions: <Type, Action<Intent>>{
        SwitchTabIntent: CallbackAction<SwitchTabIntent>(onInvoke: (i) {
          switchTab(i.index);
          return null;
        }),
        NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) {
          nextTab();
          return null;
        }),
        PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) {
          prevTab();
          return null;
        }),
        RefreshIntent: CallbackAction<RefreshIntent>(onInvoke: (_) {
          refreshResults();
          return null;
        }),
        ToggleEditModeIntent: CallbackAction<ToggleEditModeIntent>(onInvoke: (_) {
          ref.read(editModeProvider.notifier).state = !ref.read(editModeProvider);
          return null;
        }),
        RunSubscriptionIntent: CallbackAction<RunSubscriptionIntent>(onInvoke: (_) {
          ref.read(subProvider.notifier).runSubscription();
          return null;
        }),
        CancelRunIntent: CallbackAction<CancelRunIntent>(onInvoke: (_) {
          ref.read(subProvider.notifier).cancel();
          return null;
        }),
      },
      child: Shortcuts(
        shortcuts: buildAppShortcuts(),
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: appBar,
            body: sideRail != null
                ? Row(children: [sideRail, body])
                : body,
            bottomNavigationBar: bottomNav,
          ),
        ),
      ),
    );
  }
}

/// Animated tab stack: holds three tabs (Config, Run, Results) with
/// slide + fade transitions on tab switch. All children stay alive via
/// [AutomaticKeepAliveClientMixin].
class _TabStack extends StatefulWidget {
  final int tab;
  const _TabStack({required this.tab});

  @override
  State<_TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<_TabStack> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late CurvedAnimation _curve;
  late Animation<double> _oldFade; // 1.0 → 0.0 (fade out)
  late Animation<double> _newFade; // 0.0 → 1.0 (fade in)
  late Animation<Offset> _newSlide;
  int _prevTab = 0;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: Motion.durBase, vsync: this)
      ..addStatusListener(_onStatus);
    _curve = CurvedAnimation(parent: _ctrl, curve: Motion.curveStandard);
    _buildAnimations(0);
    _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl
      ..removeStatusListener(_onStatus)
      ..dispose();
    _curve.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      setState(() => _animating = false);
    }
  }

  void _buildAnimations(int delta) {
    _oldFade = Tween(begin: 1.0, end: 0.0).animate(_curve);
    _newFade = Tween(begin: 0.0, end: 1.0).animate(_curve);
    _newSlide =
        Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(_curve);
  }

  @override
  void didUpdateWidget(covariant _TabStack old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      if (_animating) _ctrl.value = 1.0;
      _prevTab = old.tab;
      _animating = true;
      _buildAnimations(widget.tab - _prevTab);
      _ctrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < _children.length; i++)
          if (i == widget.tab)
            FadeTransition(
              opacity: _newFade,
              child: SlideTransition(position: _newSlide, child: _children[i]),
            )
          else if (i == _prevTab && _animating)
            FadeTransition(opacity: _oldFade, child: _children[i])
          else
            Offstage(offstage: true, child: _children[i]),
      ],
    );
  }

  static const _children = [
    ConfigTab(),
    RunTab(),
    ResultsTab(),
    GithubSyncTab(),
  ];
}