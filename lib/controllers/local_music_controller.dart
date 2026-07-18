import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/music_models.dart';

class LocalMusicController extends ChangeNotifier {
  LocalMusicController() {
    _checkPermission();
  }

  static const _channel = MethodChannel('kgka_music_hl/local_music');

  bool _hasPermission = false;
  List<Song> _songs = [];
  bool _isScanning = false;

  static const _maxAlbumArtCacheSize = 50;
  final _albumArtCache = LinkedHashMap<String, Uint8List>();

  bool get hasPermission => _hasPermission;
  List<Song> get songs => _songs;
  bool get isScanning => _isScanning;

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final granted = await _channel.invokeMethod<bool>('hasPermission') ?? false;
      _hasPermission = granted;
      notifyListeners();
      if (_hasPermission) {
        await scanLocalMusic();
      }
    } catch (e) {
      debugPrint('Error checking audio permission: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission') ?? false;
      _hasPermission = granted;
      notifyListeners();
      if (_hasPermission) {
        await scanLocalMusic();
      }
      return granted;
    } catch (e) {
      debugPrint('Error requesting audio permission: $e');
      return false;
    }
  }

  Future<void> scanLocalMusic() async {
    if (!Platform.isAndroid) return;
    if (!_hasPermission) return;

    _isScanning = true;
    notifyListeners();

    try {
      final List<dynamic> result = await _channel.invokeMethod('getLocalSongs');
      final List<Song> list = [];

      for (final item in result) {
        if (item is Map) {
          final filePath = item['filePath'] as String? ?? '';
          final title = item['title'] as String? ?? '未知歌曲';
          final artist = item['artist'] as String? ?? '未知艺人';
          final durationMs = item['duration'] as int?;

          if (filePath.isNotEmpty) {
            list.add(Song(
              id: filePath,
              title: title,
              artist: artist,
              hash: filePath,
              coverUrl: item['albumArtUri'] as String?,
              duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
              source: SongSource.local,
            ));
          }
        }
      }

      _songs = list;
    } catch (e) {
      debugPrint('Error scanning local music: $e');
    }

    _isScanning = false;
    notifyListeners();
  }

  /// 获取本地歌曲的专辑封面字节数据（带缓存）。
  Future<Uint8List?> getAlbumArt(String albumId) async {
    if (!Platform.isAndroid) return null;
    if (_albumArtCache.containsKey(albumId)) {
      return _albumArtCache[albumId];
    }
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'getAlbumArt',
        {'albumId': int.tryParse(albumId)},
      );
      if (bytes != null) {
        _albumArtCache[albumId] = bytes;
        if (_albumArtCache.length > _maxAlbumArtCacheSize) {
          _albumArtCache.remove(_albumArtCache.keys.first);
        }
      }
      return bytes;
    } catch (e) {
      debugPrint('Error getting album art: $e');
      return null;
    }
  }

  /// 获取本地歌曲的内嵌歌词。
  Future<String?> getEmbeddedLyrics(String filePath) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>(
        'getEmbeddedLyrics',
        {'filePath': filePath},
      );
    } catch (e) {
      debugPrint('Error getting embedded lyrics: $e');
      return null;
    }
  }
}
