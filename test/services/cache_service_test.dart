// 数据缓存的大小统计与清理范围一致性回归测试：
// shiyin_cached_playlists_*（歌单缓存旧版双写 key）计入大小统计后，
// 「清理数据缓存」也必须一并清除，否则清理提示成功但大小几乎不变。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiyin_music/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getCacheSize/getCacheCount 与 clearAllCache 覆盖同一批 key', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cache_home': '{"savedAt":1,"payload":{}}',
      'cache_playlist_42': '{"savedAt":1,"payload":{}}',
      // 歌单缓存旧版双写 key：计入统计，也必须被清理。
      'shiyin_cached_playlists_42': '[{"id":"a"},{"id":"b"}]',
      // 非数据缓存：登出凭证等不得被「清理数据缓存」动到。
      'shiyin_token': 'secret',
      'shiyin_liked_hashes': '[]',
    });

    final service = CacheService();
    expect(await service.getCacheCount(), 3);
    expect(await service.getCacheSize(), greaterThan(0));

    await service.clearAllCache();

    expect(await service.getCacheCount(), 0);
    expect(await service.getCacheSize(), 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shiyin_token'), 'secret');
    expect(prefs.getString('shiyin_liked_hashes'), '[]');
    expect(prefs.getKeys(), unorderedEquals(<String>['shiyin_token', 'shiyin_liked_hashes']));
  });

  test('登出清理只动用户相关前缀，保留匿名缓存', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cache_home': '{}',
      'cache_user_playlists_42': '{}',
      'cache_playlist_42': '{}',
      'cache_artist_42': '{}',
      'shiyin_cached_playlists_42': '[]',
    });

    final service = CacheService();
    await service.clearUserCache(null);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cache_home'), '{}');
    expect(prefs.getString('cache_user_playlists_42'), isNull);
    expect(prefs.getString('cache_playlist_42'), isNull);
    expect(prefs.getString('cache_artist_42'), isNull);
  });
}
