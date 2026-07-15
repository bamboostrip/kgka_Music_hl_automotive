import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

import 'config/app_config.dart';
import 'controllers/auth_controller.dart';
import 'controllers/download_controller.dart';
import 'controllers/player_controller.dart';
import 'controllers/theme_controller.dart';
import 'controllers/local_music_controller.dart';
import 'core/api_client.dart';
import 'services/cache_service.dart';
import 'services/download_service.dart';
import 'services/music_api.dart';
import 'ui/pages/app_shell.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/player_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.loadCustomBaseUrl();
  await AudioService.init(
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hoilai.mm.music.channel.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
    builder: () => AppAudioHandler(),
  );
  runApp(const KaMusicApp());
}

class KaMusicApp extends StatefulWidget {
  const KaMusicApp({super.key});

  @override
  State<KaMusicApp> createState() => _KaMusicAppState();
}

class _KaMusicAppState extends State<KaMusicApp> with WidgetsBindingObserver {
  late final ApiClient _client;
  late final MusicApi _api;
  late final CacheService _cacheService;
  late final DownloadService _downloadService;
  late final AuthController _auth;
  late final PlayerController _player;
  late final DownloadController _downloads;
  late final ThemeController _theme;
  late final LocalMusicController _localMusic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _api = MusicApi(_client);
    _cacheService = CacheService();
    _downloadService = DownloadService();
    _downloads = DownloadController(_downloadService, _api);
    _auth = AuthController(_api, _cacheService);
    _player = PlayerController(_api, widget.audioHandler);
    _theme = ThemeController();
    _localMusic = LocalMusicController();
    _auth.restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.dispose();
    _player.dispose();
    _downloads.dispose();
    _localMusic.dispose();
    _downloadService.dispose();
    _client.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 从后台恢复时静默触发一次每日 VIP 领取（受开关与当日去重约束）。
    if (state == AppLifecycleState.resumed) {
      _auth.vipClaim.schedule(_auth.session);
    }
    if (!_player.desktopLyricsEnabled) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _player.setAppForeground(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _player.setAppForeground(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _theme,
      builder: (context, _) {
        return MaterialApp(
          title: 'kgka Music',
          debugShowCheckedModeBanner: false,
          theme: _theme.themeData,
          home: AnimatedBuilder(
            animation: _auth,
            builder: (context, _) {
              if (_auth.isRestoring) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (!_auth.isLoggedIn) {
                return LoginPage(api: _api, auth: _auth);
              }
              return AppShell(
                api: _api,
                auth: _auth,
                player: _player,
                theme: _theme,
                downloads: _downloads,
                localMusic: _localMusic,
                cache: _cacheService,
              );
            },
          ),
        );
      },
    );
  }
}
