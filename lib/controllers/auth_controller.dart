import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';
import '../services/music_api.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._api);

  static const _tokenKey = 'ka_music_token';
  static const _t1Key = 'ka_music_t1';
  static const _userIdKey = 'ka_music_user_id';

  final MusicApi _api;

  bool isLoading = false;
  String? errorMessage;
  LoginSession? session;
  UserProfile? profile;
  List<PlaylistSummary> playlists = const [];

  bool get isLoggedIn => session?.isValid == true;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final restored = LoginSession(
      userId: prefs.getString(_userIdKey),
      token: prefs.getString(_tokenKey),
      t1: prefs.getString(_t1Key),
    );

    if (!restored.isValid) {
      return;
    }

    session = restored;
    _api.setSession(restored);
    notifyListeners();
    await refreshProfile();
  }

  Future<void> sendCode(String mobile) async {
    await _run(() => _api.sendLoginCode(mobile));
  }

  Future<void> login(String mobile, String code) async {
    await _run(() async {
      final nextSession = await _api.loginWithPhone(mobile: mobile, code: code);
      session = nextSession;
      _api.setSession(nextSession);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, nextSession.token ?? '');
      await prefs.setString(_t1Key, nextSession.t1 ?? '');
      await prefs.setString(_userIdKey, nextSession.userId ?? '');

      await refreshProfile(silent: true);
    });
  }

  Future<void> refreshProfile({bool silent = false}) async {
    await _run(() async {
      profile = await _api.userDetail();
      playlists = await _api.userPlaylists();
    }, silent: silent);
  }

  Future<void> logout() async {
    await _run(() async {
      try {
        await _api.logout();
      } finally {
        session = null;
        profile = null;
        playlists = const [];
        _api.setSession(null);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_tokenKey);
        await prefs.remove(_t1Key);
        await prefs.remove(_userIdKey);
      }
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool silent = false,
  }) async {
    if (!silent) {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
    }

    try {
      await action();
      errorMessage = null;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
