import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/config/config_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/results/results_page.dart';
import '../features/settings/settings_page.dart';
import 'theme.dart';

enum PageKey { dashboard, config, results, settings }

final pageProvider = StateProvider<PageKey>((ref) => PageKey.dashboard);
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(pageProvider);
    final isWide = MediaQuery.of(context).size.width >= 760;

    final content = _pageWidget(page);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(ref: ref, current: page),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      body: content,
      bottomNavigationBar: _BottomNav(ref: ref, current: page),
    );
  }

  Widget _pageWidget(PageKey p) {
    switch (p) {
      case PageKey.dashboard:
        return const DashboardPage();
      case PageKey.config:
        return const ConfigPage();
      case PageKey.results:
        return const ResultsPage();
      case PageKey.settings:
        return const SettingsPage();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final WidgetRef ref;
  final PageKey current;
  const _Sidebar({required this.ref, required this.current});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final railColor = const Color(0xFF101A2B);
    return Container(
      width: 88,
      color: railColor,
      child: Column(
        children: [
          const SizedBox(height: 22),
          // 品牌 Logo：青绿→蓝渐变圆角块
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [t.primary, t.info],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.cloud, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 24),
          for (final item in const [
            (PageKey.dashboard, Icons.dashboard_outlined, Icons.dashboard, '工作台'),
            (PageKey.config, Icons.tune, Icons.tune, '优选配置'),
            (PageKey.results, Icons.bar_chart, Icons.bar_chart, '结果'),
            (PageKey.settings, Icons.settings_outlined, Icons.settings, '设置'),
          ])
            _NavItem(
              icon: current == item.$1 ? item.$3 : item.$2,
              label: item.$4,
              active: current == item.$1,
              activeColor: t.primary,
              onTap: () => ref.read(pageProvider.notifier).state = item.$1,
            ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: Colors.white70,
            ),
            tooltip: '切换主题',
            onPressed: () => ref.read(themeModeProvider.notifier).state =
                Theme.of(context).brightness == Brightness.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 62,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            if (active)
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 20,
                      color: active ? activeColor : Colors.white60),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                        fontSize: 11,
                        color: active ? activeColor : Colors.white60,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final WidgetRef ref;
  final PageKey current;
  const _BottomNav({required this.ref, required this.current});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return NavigationBar(
      selectedIndex: PageKey.values.indexOf(current),
      indicatorColor: t.primarySoft,
      onDestinationSelected: (i) => ref.read(pageProvider.notifier).state = PageKey.values[i],
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: '工作台'),
        NavigationDestination(icon: Icon(Icons.tune), label: '优选配置'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: '结果'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
      ],
    );
  }
}