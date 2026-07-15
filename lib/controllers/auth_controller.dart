import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../core/api_client.dart';
import '../models/music_models.dart';
import '../services/cache_service.dart';
import '../services/music_api.dart';
import '../services/vip_background_task.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._api, this._cacheService);

  static const _tokenKey = 'ka_music_token';
  static const _t1Key = 'ka_music_t1';
  static const _sessionIdKey = 'ka_music_session_id';
  static const _userIdKey = 'ka_music_user_id';
  static const _playlistCachePrefix = 'ka_music_cached_playlists';
  static const _playlistEmptyCountPrefix = 'ka_music_playlist_empty_count';
  static const _likedHashesKey = 'ka_music_liked_hashes';
  final MusicApi _api;
  final CacheService _cacheService;
  late final VipBackgroundTask _vipBackgroundTask = VipBackgroundTask(_api);

  /// 自动领取 VIP 任务，供设置页绑定开关 / 立即领取 / 状态展示。
  VipBackgroundTask get vipClaim => _vipBackgroundTask;

  bool isRestoring = true;
  bool isLoading = false;
  String? errorMessage;
  LoginSession? session;
  UserProfile? profile;
  List<PlaylistSummary> playlists = const [];

  final Set<String> _likedHashes = {};

  bool get isLoggedIn => session?.isValid == true;

  bool isLiked(Song song) => _likedHashes.contains(song.hash);

  int get likedCount {
    final playlist = likedPlaylist;
    if (playlist != null && playlist.songCount != null) {
      return playlist.songCount!;
    }
    return _likedHashes.length;
  }

  Future<void> toggleLike(Song song) async {
    final playlist = likedPlaylist;
    if (playlist == null) return;

    final liked = _likedHashes.contains(song.hash);
    final targetListId = playlist.listId?.isNotEmpty == true
        ? playlist.listId!
        : playlist.id;
    try {
      if (liked) {
        await _api.removeFromPlaylist(targetListId, song);
        _likedHashes.remove(song.hash);
      } else {
        await _api.addToPlaylist(targetListId, song);
        _likedHashes.add(song.hash);
      }
      notifyListeners();
    } catch (_) {}
  }

  Playlist? get likedPlaylist => playlists
      .whereType<Playlist>()
      .where((p) => p.isLikedPlaylist)
      .firstOrNull;

  Future<void> refreshProfile({bool silent = false}) async {
    if (!silent) {
      isLoading = true;
      notifyListeners();
    }
    try {
      final result = await _api.userDetail();
      profile = result;
      await _cacheService.write(_userCacheKey, UserProfile.toCache(result));
    } catch (_) {}
    if (!silent) {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedUserId = prefs.getString(_userIdKey);
      final restored = LoginSession(
        userId: storedUserId,
        token: prefs.getString(_tokenKey),
        t1: prefs.getString(_t1Key),
        sessionId: prefs.getString(_sessionIdKey),
      );

      if (!restored.isValid) {
        return;
      }

      session = restored;
      _api.setSession(restored);

      try {
        final refreshed = await _api.refreshToken();
        if (storedUserId != null &&
            refreshed.userId != null &&
            storedUserId != refreshed.userId) {
          await _clearSession();
          return;
        }
        session = refreshed;
        _api.setSession(refreshed);
        await prefs.setString(_tokenKey, refreshed.token ?? '');
        await prefs.setString(_t1Key, refreshed.t1 ?? '');
        await prefs.setString(_userIdKey, refreshed.userId ?? '');
      } catch (_) {
        // /login/token failed, continue with stored token
      }

      playlists = await _loadCachedPlaylists();
      await _loadLikedHashes();
      // 先读缓存的用户信息，静默刷新由 refreshProfile 完成
      final cachedProfile = await _cacheService.read<UserProfile>(
        _userCacheKey,
        decode: UserProfile.fromCache,
        ttl: AppConfig.userProfileTtl,
      );
      if (cachedProfile != null) {
        profile = cachedProfile.data;
      }
      // 缓存数据已就绪，立即通知 UI 显示，API 刷新在后台进行
      isRestoring = false;
      notifyListeners();
      await refreshProfile(silent: true);
      await _vipBackgroundTask.loadPrefsOnce();
      _vipBackgroundTask.schedule(session);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String mobile, String code) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final session = await _api.login(mobile, code);
      if (session.userId == null || session.token == null) {
        errorMessage = '登录失败，请检查验证码';
        return;
      }
      this.session = session;
      _api.setSession(session);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, session.token ?? '');
      await prefs.setString(_t1Key, session.t1 ?? '');
      await prefs.setString(_userIdKey, session.userId ?? '');
      await refreshProfile(silent: true);
      _vipBackgroundTask.schedule(session);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loginWithSession(Map<String, dynamic> sessionData) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final session = LoginSession.fromJson(sessionData);
      this.session = session;
      _api.setSession(session);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, session.token ?? '');
      await prefs.setString(_t1Key, session.t1 ?? '');
      await prefs.setString(_userIdKey, session.userId ?? '');
      await refreshProfile(silent: true);
      _vipBackgroundTask.schedule(session);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _clearSession();
    session = null;
    profile = null;
    playlists = const [];
    _likedHashes.clear();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_t1Key);
    await prefs.remove(_sessionIdKey);
    await prefs.remove(_userIdKey);
    _api.setSession(null);
  }

  Future<List<PlaylistSummary>> _loadCachedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_playlistCachePrefix));
    final playlists = <PlaylistSummary>[];
    for (final key in keys) {
      final json = prefs.getString(key);
      if (json != null) {
        try {
          playlists.add(PlaylistSummary.fromJson(jsonDecode(json)));
        } catch (_) {}
      }
    }
    return playlists;
  }

  Future<void> _loadLikedHashes() async {
    final prefs = await SharedPreferences.getInstance();
    final hashes = prefs.getStringList(_likedHashesKey);
    if (hashes != null) {
      _likedHashes.addAll(hashes);
    }
  }

  static const _userCacheKey = 'cache_user_profile';
}
