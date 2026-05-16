import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../services/music_api.dart';
import '../widgets/mini_player.dart';
import 'home_page.dart';
import 'library_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final pages = [
      HomePage(api: widget.api, auth: widget.auth, player: widget.player),
      LibraryPage(api: widget.api, auth: widget.auth, player: widget.player),
    ];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: pages[_index]),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + kBottomNavigationBarHeight + 10,
            child: MiniPlayer(player: widget.player),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        backgroundColor: colorScheme.surface.withValues(alpha: .96),
        elevation: 0,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurface,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
