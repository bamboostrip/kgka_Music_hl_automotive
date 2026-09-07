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
      final restored = RankCategory.fromCache(rank.toCache());
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
      final restoredStation = FmStation.fromCache(station.toCache());
      expect(restoredStation.id, 'fm1');
      expect(restoredStation.previewSongs.map((s) => s.hash), ['h1']);

      final restoredGroup = FmClassGroup.fromCache(group.toCache());
      expect(restoredGroup.id, 'g1');
      expect(restoredGroup.stations.map((s) => s.id), ['fm1']);
    });
  });
}
