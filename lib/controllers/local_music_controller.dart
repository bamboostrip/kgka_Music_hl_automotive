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
}
