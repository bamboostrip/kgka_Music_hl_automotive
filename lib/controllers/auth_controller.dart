import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';
import '../services/music_api.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._api);

  static const _tokenKey = 'ka_music_token';
  static const _t1Key = 'ka_music_t1';
  static const _userIdKey = 'ka_music_user_id';
  static const _playlistCachePrefix = 'ka_music_cached_playlists';
  static const _playlistEmptyCountPrefix = 'ka_music_playlist_empty_count';

  final MusicApi _api;

  bool isLoading = false;
  String? errorMessage;
  LoginSession? session;
  UserProfile? profile;
  List<PlaylistSummary> playlists = const [];

  bool get isLoggedIn => session?.isValid == true;

  PlaylistSummary? get likedPlaylist {
    for (final playlist in playlists) {
      if (playlist.isLikedPlaylist) {
        return playlist;
      }
    }
    return null;
  }

  List<PlaylistSummary> get createdPlaylists {
    return playlists
        .where(
          (playlist) =>
              !playlist.isLikedPlaylist && _isCreatedPlaylist(playlist),
        )
        .toList();
  }

  List<PlaylistSummary> get collectedPlaylists {
    return playlists
        .where(
          (playlist) =>
              !playlist.isLikedPlaylist && !_isCreatedPlaylist(playlist),
        )
        .toList();
  }

  bool _isCreatedPlaylist(PlaylistSummary playlist) {
    if (playlist.isCreatedPlaylist) {
      return true;
    }
    final nickname = profile?.nickname.trim();
    if (nickname != null &&
        nickname.isNotEmpty &&
        playlist.creatorName?.trim() == nickname) {
      return true;
    }
    if (playlist.isDefault == null &&
        playlist.creatorUserId == null &&
        !playlist.hasCollectionSource) {
      return true;
    }
    return false;
  }

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
    playlists = await _loadCachedPlaylists();
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
      playlists = await _loadUserPlaylistsWithCache();
    }, silent: silent);
  }

  Future<void> logout() async {
    await _run(() async {
      try {
        await _api.logout();
      } finally {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = _playlistCacheKey;
        final emptyCountKey = _playlistEmptyCountKey;
        session = null;
        profile = null;
        playlists = const [];
        _api.setSession(null);
        await prefs.remove(_tokenKey);
        await prefs.remove(_t1Key);
        await prefs.remove(_userIdKey);
        await prefs.remove(cacheKey);
        await prefs.remove(emptyCountKey);
      }
    });
  }

  Future<List<PlaylistSummary>> _loadUserPlaylistsWithCache() async {
    final prefs = await SharedPreferences.getInstance();
    final fetched = await _api.userPlaylists(pageSize: 100);

    if (fetched.isNotEmpty) {
      await prefs.setInt(_playlistEmptyCountKey, 0);
      await _saveCachedPlaylists(fetched);
      return fetched;
    }

    final emptyCount = (prefs.getInt(_playlistEmptyCountKey) ?? 0) + 1;
    await prefs.setInt(_playlistEmptyCountKey, emptyCount);

    final cached = await _loadCachedPlaylists();
    if (cached.isNotEmpty && emptyCount < 2) {
      return cached;
    }

    await prefs.remove(_playlistCacheKey);
    return const [];
  }

  Future<List<PlaylistSummary>> _loadCachedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistCacheKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final json = jsonDecode(raw);
      if (json is! List) {
        return const [];
      }
      return json
          .whereType<Map>()
          .map((item) => PlaylistSummary.fromCache(asMap(item)))
          .where((playlist) => playlist.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCachedPlaylists(List<PlaylistSummary> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistCacheKey,
      jsonEncode(playlists.map((playlist) => playlist.toCache()).toList()),
    );
  }

  String get _playlistCacheKey {
    return '${_playlistCachePrefix}_${session?.userId ?? 'default'}';
  }

  String get _playlistEmptyCountKey {
    return '${_playlistEmptyCountPrefix}_${session?.userId ?? 'default'}';
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
