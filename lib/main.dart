import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'controllers/auth_controller.dart';
import 'controllers/player_controller.dart';
import 'core/api_client.dart';
import 'services/music_audio_handler.dart';
import 'services/music_api.dart';
import 'ui/app_theme.dart';
import 'ui/pages/app_shell.dart';
import 'ui/pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  await AppConfig.loadCustomBaseUrl();

  final client = ApiClient();
  final api = MusicApi(client);
  final audioHandler = await AudioService.init(
    builder: MusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'kgka_music_hl.playback',
      androidNotificationChannelName: 'KA Music 播放控制',
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(KaMusicApp(client: client, api: api, audioHandler: audioHandler));
}

class KaMusicApp extends StatefulWidget {
  const KaMusicApp({
    super.key,
    required this.client,
    required this.api,
    required this.audioHandler,
  });

  final ApiClient client;
  final MusicApi api;
  final MusicAudioHandler audioHandler;

  @override
  State<KaMusicApp> createState() => _KaMusicAppState();
}

class _KaMusicAppState extends State<KaMusicApp> {
  late final ApiClient _client;
  late final MusicApi _api;
  late final AuthController _auth;
  late final PlayerController _player;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _api = widget.api;
    _auth = AuthController(_api);
    _player = PlayerController(_api, widget.audioHandler);
    _auth.restore();
  }

  @override
  void dispose() {
    _auth.dispose();
    _player.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (context, child) {
        return _SystemUiOverlay(child: child ?? const SizedBox.shrink());
      },
      home: AnimatedBuilder(
        animation: _auth,
        builder: (context, _) {
          if (!_auth.isRestoring && !_auth.isLoggedIn) {
            return LoginPage(auth: _auth);
          }

          return AppShell(api: _api, auth: _auth, player: _player);
        },
      ),
    );
  }
}

class _SystemUiOverlay extends StatelessWidget {
  const _SystemUiOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: colorScheme.surface,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: child,
    );
  }
}
