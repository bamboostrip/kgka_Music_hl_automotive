import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/models/fm.dart';
import 'package:shiyin_music/models/search_rank.dart';
import 'package:shiyin_music/models/song.dart';

Song _testSong(String hash) {
  return Song(
    id: 'id_$hash',
    title: 'title_$hash',
    artist: 'artist',
    hash: hash,
  );
}

/// 走真实持久化链路：toCache → jsonEncode → jsonDecode → fromCache。
/// 直通 Map 会漏掉「混入非 JSON 原生类型」这类只在编码时暴露的问题。
Map<String, dynamic> _roundtrip(Map<String, dynamic> json) {
  return jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}

void main() {
  group('rank/radio cache roundtrip', () {
    test('RankCategory toCache/fromCache preserves list', () {
      final rank = RankCategory(
        rankId: 1,
        rankName: '飙升榜',
        rankType: 1,
        imageUrl: 'https://example.com/cover.jpg',
        updateFrequency: '每天更新',
        songs: [_testSong('a'), _testSong('b')],
        children: const [],
      );
      final restored = RankCategory.fromCache(_roundtrip(rank.toCache()));
      expect(restored.rankId, 1);
      expect(restored.rankName, '飙升榜');
      expect(restored.songs.map((s) => s.hash), ['a', 'b']);
    });

    test('FmStation/FmClassGroup toCache/fromCache preserves data', () {
      final station = FmStation(
        id: 'fm1',
        name: '电台1',
        type: 2,
        previewSongs: [_testSong('h1')],
      );
      final group = FmClassGroup(
        id: 'g1',
        name: '分类1',
        stations: [station],
      );
      final restoredStation = FmStation.fromCache(_roundtrip(station.toCache()));
      expect(restoredStation.id, 'fm1');
      expect(restoredStation.previewSongs.map((s) => s.hash), ['h1']);

      final restoredGroup = FmClassGroup.fromCache(_roundtrip(group.toCache()));
      expect(restoredGroup.id, 'g1');
      expect(restoredGroup.stations.map((s) => s.id), ['fm1']);
    });

    test('Song.fromCache 不对已清洗标题二次清洗', () {
      // cleanSongTitle 非幂等：首趟保留原样的标题，二趟会被继续切割。
      // toCache 写入的 title 已是清洗结果，fromCache 必须原样使用。
      const json = {
        'id': 's1',
        'title': 'X - Y - Z',
        'artist': 'Y Z',
        'hash': 'hash1',
      };
      final restored = Song.fromCache(_roundtrip(json));
      expect(restored.title, 'X - Y - Z');
    });

    test('Song.fromCache 不把清洗后标题回填成 rawTitle', () {
      const json = {
        'id': 's1',
        'title': '晴天',
        'artist': '周杰伦',
        'hash': 'hash1',
      };
      final restored = Song.fromCache(_roundtrip(json));
      expect(restored.rawTitle, isNull);
    });

    test('Song.fromCache 对 {size} 占位符封面做 normalize', () {
      const json = {
        'id': 's1',
        'title': '晴天',
        'artist': '周杰伦',
        'hash': 'hash1',
        'coverUrl': 'https://img.example.com/{size}_1.jpg',
      };
      final restored = Song.fromCache(_roundtrip(json));
      expect(restored.coverUrl, 'https://img.example.com/480_1.jpg');
    });

    test('rankId 为 0 的缓存项由消费侧过滤（与 API 层对齐）', () {
      final restored = RankCategory.fromCache(_roundtrip({
        'rankId': 0,
        'rankName': '坏数据',
      }));
      expect(restored.rankId, 0);
      // 消费侧（rank_page._initFromDiskOrNetwork）以 rankId > 0 过滤，
      // 这里只断言模型层不抛错且保留原值，供 UI 侧过滤。
    });
  });
}
