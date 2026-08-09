import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/results/results_tab.dart';
import '../features/results/result_state.dart';
import '../features/subscriptions/config_tab.dart';
import '../features/subscriptions/run_tab.dart';
import '../features/subscriptions/subscriptions_state.dart';
import 'breakpoints.dart';
import 'motion.dart';
import 'platform.dart';
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
    void nextTab() => switchTab((ref.read(tabProvider) + 1) % 3);
    void prevTab() => switchTab((ref.read(tabProvider) - 1 + 3) % 3);
    void refreshResults() {
      final cfg = ref.read(configProvider).value;
      if (cfg != null) {
        ref.read(resultProvider.notifier).loadFile(cfg.subLatencyOutputFile);
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
              color: AppTheme.edgeOrange,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.cloud_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('CF优选', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
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

    // ── 中型及以上（>=600dp）→ NavigationRail ──
    if (formFactor != FormFactor.compact) {
      sideRail = NavigationRail(
        selectedIndex: tab,
        onDestinationSelected: switchTab,
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: IconThemeData(color: AppTheme.edgeOrange, size: 24),
        unselectedIconTheme: IconThemeData(color: t.textDim),
        selectedLabelTextStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.edgeOrange),
        unselectedLabelTextStyle: TextStyle(fontSize: 13, color: t.textDim),
        destinations: const [
          NavigationRailDestination(icon: Icon(Icons.tune), label: Text('配置')),
          NavigationRailDestination(icon: Icon(Icons.play_arrow), label: Text('运行')),
          NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('结果')),
        ],
      );
      body = Expanded(child: _TabStack(tab: tab));
    } else {
      // ── 紧凑（<600dp）→ 底部 NavigationBar ──
      bottomNav = SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: switchTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.tune), label: '配置'),
            NavigationDestination(icon: Icon(Icons.play_arrow), label: '运行'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: '结果'),
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
          // 由 ResultsTab 监听 tabProvider 变化来切换（不直接访问 state）
          return null;
        }),
        RunSubscriptionIntent: CallbackAction<RunSubscriptionIntent>(onInvoke: (_) {
          ref.read(subProvider.notifier).runSubscription();
          return null;
        }),
        RunLatencyIntent: CallbackAction<RunLatencyIntent>(onInvoke: (_) {
          ref.read(subProvider.notifier).runLatency();
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

/// IndexedStack + 淡入叠加层过渡。
/// 永久持有三页（不销毁），切 Tab 时叠一层共享 Z 轴过渡（fade + scale）。
class _TabStack extends StatefulWidget {
  final int tab;
  const _TabStack({required this.tab});

  @override
  State<_TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<_TabStack> with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: Motion.durBase);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Motion.curveStandard);
    _scaleAnim = Tween(begin: 0.97, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Motion.curveStandard));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TabStack old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      _fadeCtrl.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IndexedStack(
          index: widget.tab,
          children: const [
            ConfigTab(),
            RunTab(),
            ResultsTab(),
          ],
        ),
        FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
