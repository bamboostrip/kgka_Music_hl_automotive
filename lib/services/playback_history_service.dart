import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';

/// 播放历史记录服务。
///
/// 将最近播放过的歌曲按时间倒序持久化到 SharedPreferences（JSON 格式），
/// 同一首歌重复播放时会移动到列表头部，最多保留 [_maxRecords] 条。
class PlaybackHistoryService {
  static const _key = 'playback_history';
  static const _maxRecords = 500;

  /// 记录一次播放：去重后插入到头部，超出上限时截断。
  Future<void> record(Song song) async {
    if (song.hash.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    List<dynamic> list = [];
    if (raw != null) {
      try {
        list = jsonDecode(raw) as List;
      } catch (_) {}
    }
    // 去重：移除同 hash 的旧记录
    list.removeWhere((item) {
      if (item is! Map) return false;
      return item['hash'] == song.hash;
    });
    // 插入到头部
    list.insert(0, song.toCache());
    // 限制数量
    if (list.length > _maxRecords) {
      list = list.sublist(0, _maxRecords);
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  /// 读取播放历史，最多返回 [limit] 条。
  Future<List<Song>> getHistory({int limit = 100}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(Song.fromCache)
          .where((s) => s.hash.isNotEmpty)
          .take(limit)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 读取历史记录总数（仅解析 JSON 长度，不反序列化 Song 对象）。
  ///
  /// 用于 UI 上的计数展示，避免为了取 length 而反序列化全部 Song。
  /// 返回值受 [_maxRecords] 上限约束。
  Future<int> count() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return 0;
    try {
      return (jsonDecode(raw) as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// 清空播放历史。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
