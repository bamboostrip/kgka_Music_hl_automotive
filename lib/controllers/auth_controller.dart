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
  static const _likedHashesKey = 'ka_music_liked_hashes';

  final MusicApi _api;

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
      await _persistLikedHashes();
      notifyListeners();
    } catch (error) {
      // Revert on failure
      if (liked) {
        _likedHashes.add(song.hash);
      } else {
        _likedHashes.remove(song.hash);
      }
      rethrow;
    }
  }

  PlaylistSummary? get likedPlaylist {
    for (final playlist in playlists) {
      if (playlist.isLikedPlaylist) {
        return playlist;
      }
    }
    return null;
  }

  List<PlaylistSummary> get createdPlaylists {
    return playlists.where((playlist) => playlist.isCreatedPlaylist).toList();
  }

  List<PlaylistSummary> get collectedPlaylists {
    return playlists
        .where(
          (playlist) =>
              !playlist.isLikedPlaylist && !playlist.isCreatedPlaylist,
        )
        .toList();
  }

  Future<void> restore() async {
    try {
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
      await _loadLikedHashes();
      await refreshProfile(silent: true);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isRestoring = false;
      notifyListeners();
    }
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
      await _syncLikedSongs();
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
        _likedHashes.clear();
        _api.setSession(null);
        await prefs.remove(_tokenKey);
        await prefs.remove(_t1Key);
        await prefs.remove(_userIdKey);
        await prefs.remove(cacheKey);
        await prefs.remove(emptyCountKey);
        await prefs.remove(_likedHashesKey);
      }
    });
  }

  Future<void> _syncLikedSongs() async {
    final playlist = likedPlaylist;
    if (playlist == null) return;

    try {
      final songs = await _api.playlistSongs(playlist.id, fetchAll: true);
      _likedHashes.clear();
      for (final song in songs) {
        _likedHashes.add(song.hash);
      }
      await _persistLikedHashes();
    } catch (_) {
      await _loadLikedHashes();
    }
  }

  Future<void> _persistLikedHashes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_likedHashesKey, jsonEncode(_likedHashes.toList()));
  }

  Future<void> _loadLikedHashes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_likedHashesKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        _likedHashes.addAll(list.whereType<String>());
      }
    } catch (_) {}
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
