import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import 'brand_overlay.dart';
import 'browser_page.dart';
import 'files_page.dart';
import 'save_page.dart';
import 'settings_page.dart';
import 'tools_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  static void go(BuildContext context, int i) => context.findAncestorStateOfType<_ShellState>()?.go(i);
  @override
  State<Shell> createState() => _ShellState();
}

List<(IconData, String)> get _nav => [
      (Icons.download_rounded, tx('حفظ', 'Save')),
      (Icons.travel_explore_rounded, tx('متصفح', 'Browser')),
      (Icons.folder_rounded, tx('ملفاتي', 'My files')),
      (Icons.handyman_rounded, tx('أدوات', 'Tools')),
      (Icons.settings_rounded, tx('الإعدادات', 'Settings')),
    ];

class _ShellState extends State<Shell> {
  int _i = 0;
  bool _browserOpened = false; // the browser stays alive in the background once opened

  void go(int i) {
    if (i == _i) return;
    BrandBus.beat();
    setState(() {
      _i = i;
      if (i == 1) _browserOpened = true;
    });
  }

  Widget _page() => switch (_i) {
        2 => const FilesPage(),
        3 => const ToolsPage(),
        4 => const SettingsPage(),
        _ => const SavePage(),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: child),
      ),
      child: KeyedSubtree(key: ValueKey(_i == 1 ? -1 : _i), child: SafeArea(bottom: false, child: _i == 1 ? const SizedBox() : _page())),
    );
    final body = Stack(children: [
      if (_browserOpened) Positioned.fill(child: Offstage(offstage: _i != 1, child: const SafeArea(bottom: false, top: false, child: BrowserPage()))),
      if (_i != 1) Positioned.fill(child: pages),
    ]);
    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          backgroundColor: c.rail,
          indicatorColor: c.accent.withValues(alpha: 0.22),
          selectedIndex: _i,
          onDestinationSelected: go,
          destinations: [for (final n in _nav) NavigationDestination(icon: Icon(n.$1), label: n.$2)],
        ),
      );
    }
    return Scaffold(
      body: Row(children: [
        Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(14, 84, 14, 20),
          decoration: BoxDecoration(color: c.rail, border: BorderDirectional(end: BorderSide(color: c.line))),
          child: Column(children: [
            for (var i = 0; i < _nav.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  decoration: BoxDecoration(
                    gradient: _i == i ? context.brandGradient : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      autofocus: _i == i,
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => go(i),
                      child: SizedBox(
                        height: 46,
                        child: Row(children: [
                          const SizedBox(width: 12),
                          Icon(_nav[i].$1, size: 20, color: _i == i ? Colors.white : c.muted),
                          const SizedBox(width: 12),
                          Text(_nav[i].$2,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: _i == i ? Colors.white : c.muted,
                                  fontWeight: _i == i ? FontWeight.w600 : FontWeight.w400)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(child: body),
      ]),
    );
  }
}
