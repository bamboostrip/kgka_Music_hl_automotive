import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'controllers/auth_controller.dart';
import 'controllers/player_controller.dart';
import 'core/api_client.dart';
import 'services/music_api.dart';
import 'ui/app_theme.dart';
import 'ui/pages/app_shell.dart';

void main() {
  runApp(const KaMusicApp());
}

class KaMusicApp extends StatefulWidget {
  const KaMusicApp({super.key});

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
    _client = ApiClient();
    _api = MusicApi(_client);
    _auth = AuthController(_api);
    _player = PlayerController(_api);
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
      home: AppShell(api: _api, auth: _auth, player: _player),
    );
  }
}
