import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../widgets/zt_motion.dart';
import '../home/home_page.dart';
import '../history/history_page.dart';
import '../profile/profile_page.dart';
import '../trends/trends_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _transitionController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  static const _pages = [
    HomePage(),
    HistoryPage(),
    TrendsPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    final curved = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0.62, end: 1).animate(curved);
    _scale = Tween<double>(begin: 0.985, end: 1).animate(curved);
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    ztHaptic(context, ZtHaptic.selection);
    if (index == _index) return;
    setState(() => _index = index);
    final reduceMotion = ztAnimationsReduced(context, listen: false);
    if (reduceMotion) {
      _transitionController.value = 1;
    } else {
      _transitionController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: IndexedStack(index: _index, children: _pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectPage,
        destinations: [
          NavigationDestination(
            icon: _NavigationIcon(
              selected: _index == 0,
              icon: Icons.edit_note_outlined,
            ),
            selectedIcon: _NavigationIcon(
              selected: _index == 0,
              icon: Icons.edit_note,
            ),
            label: '记录',
          ),
          NavigationDestination(
            icon: _NavigationIcon(
              selected: _index == 1,
              icon: Icons.history_outlined,
            ),
            selectedIcon: _NavigationIcon(
              selected: _index == 1,
              icon: Icons.history,
            ),
            label: '历史',
          ),
          NavigationDestination(
            icon: _NavigationIcon(
              selected: _index == 2,
              icon: Icons.insights_outlined,
            ),
            selectedIcon: _NavigationIcon(
              selected: _index == 2,
              icon: Icons.insights,
            ),
            label: '趋势',
          ),
          NavigationDestination(
            icon: _NavigationIcon(
              selected: _index == 3,
              icon: Icons.person_outline,
            ),
            selectedIcon: _NavigationIcon(
              selected: _index == 3,
              icon: Icons.person,
            ),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _NavigationIcon extends StatelessWidget {
  const _NavigationIcon({required this.selected, required this.icon});

  final bool selected;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = ztAnimationsReduced(context);
    return AnimatedScale(
      scale: selected ? 1 : 0.9,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Icon(icon),
    );
  }
}
