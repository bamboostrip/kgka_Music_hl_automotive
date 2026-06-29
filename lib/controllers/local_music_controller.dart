import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_models.dart';

class LocalMusicController extends ChangeNotifier {
  LocalMusicController() {
    _loadSettings();
  }

  static const _localMusicDirKey = 'settings.local_music_dir';

  String? _localMusicDir;
  List<Song> _songs = [];
  bool _isScanning = false;

  String? get localMusicDir => _localMusicDir;
  List<Song> get songs => _songs;
  bool get isScanning => _isScanning;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _localMusicDir = prefs.getString(_localMusicDirKey);
    if (_localMusicDir != null && _localMusicDir!.isNotEmpty) {
      await scanLocalMusic();
    }
  }

  Future<void> setLocalMusicDir(String? dirPath) async {
    _localMusicDir = dirPath?.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_localMusicDir != null && _localMusicDir!.isNotEmpty) {
      await prefs.setString(_localMusicDirKey, _localMusicDir!);
      await scanLocalMusic();
    } else {
      await prefs.remove(_localMusicDirKey);
      _songs = [];
      notifyListeners();
    }
  }

  Future<void> scanLocalMusic() async {
    final dirPath = _localMusicDir;
    if (dirPath == null || dirPath.isEmpty) return;

    _isScanning = true;
    notifyListeners();

    final List<Song> list = [];
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await _scanDirectory(dir, list);
      }
    } catch (e) {
      debugPrint('Error scanning local music: $e');
    }

    _songs = list;
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _scanDirectory(Directory dir, List<Song> list) async {
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is Directory) {
          // Avoid scanning system files or hidden folders
          final name = entity.uri.pathSegments.isNotEmpty
              ? (entity.uri.pathSegments.last.isEmpty && entity.uri.pathSegments.length > 1
                  ? entity.uri.pathSegments[entity.uri.pathSegments.length - 2]
                  : entity.uri.pathSegments.last)
              : entity.path.split(Platform.isWindows ? '\\' : '/').last;
          if (name.startsWith('.') || name.startsWith(r'$')) continue;
          await _scanDirectory(entity, list);
        } else if (entity is File) {
          final path = entity.path;
          final lowerPath = path.toLowerCase();
          if (lowerPath.endsWith('.mp3') ||
              lowerPath.endsWith('.m4a') ||
              lowerPath.endsWith('.flac') ||
              lowerPath.endsWith('.wav') ||
              lowerPath.endsWith('.ogg')) {
            
            // Try to parse Artist - Title from file name
            final filename = entity.uri.pathSegments.isNotEmpty 
                ? entity.uri.pathSegments.last 
                : path.split(Platform.isWindows ? '\\' : '/').last;
            final dotIndex = filename.lastIndexOf('.');
            final filenameNoExt = dotIndex != -1 ? filename.substring(0, dotIndex) : filename;
            
            String title = filenameNoExt;
            String artist = '本地音乐';
            
            if (filenameNoExt.contains(' - ')) {
              final parts = filenameNoExt.split(' - ');
              if (parts.length >= 2) {
                artist = parts[0].trim();
                title = parts.sublist(1).join(' - ').trim();
              }
            }
            
            list.add(Song(
              id: path, // use file path as song ID
              title: title,
              artist: artist,
              hash: path, // use file path as hash
              coverUrl: null,
              duration: null,
              source: SongSource.local,
            ));
          }
        }
      }
    } catch (e) {
      // Gracefully ignore directory read errors (e.g. system permissions/hidden folders)
      debugPrint('Skipping directory ${dir.path} due to error: $e');
    }
  }
}
