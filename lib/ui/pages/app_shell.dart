import 'dart:ui';

import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/download_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/local_music_controller.dart';
import '../../services/cache_service.dart';
import '../../services/music_api.dart';
import '../widgets/mini_player.dart';
import '../adaptive_layout.dart';
import 'home_page.dart';
import 'library_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.cache,
    required this.downloads,
    required this.theme,
    required this.localMusic,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final CacheService cache;
  final DownloadController downloads;
  final ThemeController theme;
  final LocalMusicController localMusic;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(api: widget.api, auth: widget.auth, player: widget.player, cache: widget.cache),
      LibraryPage(
        api: widget.api,
        auth: widget.auth,
        player: widget.player,
        downloads: widget.downloads,
        theme: widget.theme,
        localMusic: widget.localMusic,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final useNavRail = size.width >= 720;

    Widget mainContent = Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(index: _index, children: _pages),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset + (useNavRail ? 16 : kBottomNavigationBarHeight + 10),
          child: MiniPlayer(
            player: widget.player,
            auth: widget.auth,
          ),
        ),
      ],
    );

    if (useNavRail) {
      mainContent = Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            backgroundColor: colorScheme.surfaceContainerLow,
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: IconThemeData(color: colorScheme.primary),
            unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
            selectedLabelTextStyle: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
            unselectedLabelTextStyle: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: Text('首页'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: Text('我的'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: mainContent),
        ],
      );
    }

    return Scaffold(
      extendBody: true,
      body: AdaptiveContentPadding(
        child: mainContent,
      ),
      bottomNavigationBar: useNavRail
          ? null
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: .72)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: .64),
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: .38),
                      ),
                    ),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _index,
                    onTap: (value) => setState(() => _index = value),
                    backgroundColor: Colors.transparent,
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
                ),
              ),
            ),
    );
  }
}
