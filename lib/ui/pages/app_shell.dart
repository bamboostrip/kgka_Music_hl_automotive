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
    final pages = [
      HomePage(api: widget.api, auth: widget.auth, player: widget.player),
      LibraryPage(api: widget.api, auth: widget.auth, player: widget.player),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: pages[_index]),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(player: widget.player),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: '资料库',
          ),
        ],
      ),
    );
  }
}
