import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/core/api_client_interface.dart';
import 'package:shiyin_music/services/music_api.dart';

/// 假客户端：按调用顺序返回预置的 /rank/audio 响应，并记录请求参数。
class _FakeRankClient implements ApiClientInterface {
  _FakeRankClient(this.pages, {this.total, this.hashlessPerPage = 0});

  /// 每页的原始条数（songlist 长度）。
  final List<int> pages;

  /// 服务端下发的全榜单 total（null 表示响应不带 total 字段）。
  final int? total;

  /// 每页混入的无 hash 条数：模拟服务端脏数据，song 解析后会被
  /// hash 过滤掉（原始条数 > 可播条数），用于回归「按过滤后条数
  /// 判末页导致提前终止翻页」的问题。
  final int hashlessPerPage;
  final calls = <Map<String, Object?>>[];

  @override
  String? token;
  @override
  String? t1;
  @override
  String? sessionId;

  Map<String, Object?> _song(int i) => {
        'hash': 'hash$i',
        'filename': '歌手 - 歌曲$i',
        'singername': '歌手',
      };

  Map<String, Object?> _hashlessSong(int i) => {
        'hash': '',
        'filename': '歌手 - 脏数据$i',
        'singername': '歌手',
      };

  @override
  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) async {
    calls.add({'path': path, ...query});
    if (path != '/rank/audio') {
      throw ArgumentError('unexpected path: $path');
    }
    final pageIndex = calls.length - 1;
    final count = pageIndex < pages.length ? pages[pageIndex] : 0;
    return {
      if (total != null) 'total': total,
      'songlist': [
        for (var i = 0; i < count; i++)
          i < hashlessPerPage ? _hashlessSong(pageIndex * 100 + i) : _song(pageIndex * 100 + i),
      ],
    };
  }

  @override
  Future<dynamic> getRaw(Uri uri) async => throw UnimplementedError();

  @override
  Future<dynamic> post(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
  }) async => throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  group('MusicApi.rankAudioAll', () {
    test('多页榜单循环拉全：50+50+30 时应请求 3 页并返回 130 首', () async {
      final client = _FakeRankClient([50, 50, 30]);
      final api = MusicApi(client);

      final songs = await api.rankAudioAll(rankId: 8888, pageSize: 50);

      expect(songs.length, 130);
      expect(client.calls.length, 3);
      expect(client.calls[0]['page'], 1);
      expect(client.calls[1]['page'], 2);
      expect(client.calls[2]['page'], 3);
      expect(client.calls[0]['pagesize'], 50);
    });

    test('不足一页时只请求一次：30 首直接返回', () async {
      final client = _FakeRankClient([30]);
      final api = MusicApi(client);

      final songs = await api.rankAudioAll(rankId: 8888, pageSize: 50);

      expect(songs.length, 30);
      expect(client.calls.length, 1);
    });

    test('空榜单返回空列表且只请求一次', () async {
      final client = _FakeRankClient([0]);
      final api = MusicApi(client);

      final songs = await api.rankAudioAll(rankId: 8888, pageSize: 50);

      expect(songs, isEmpty);
      expect(client.calls.length, 1);
    });

    test('maxPages 防御上限：异常数据持续返回满页时也最多翻 maxPages 页', () async {
      final client = _FakeRankClient([50, 50, 50, 50, 50]);
      final api = MusicApi(client);

      final songs = await api.rankAudioAll(rankId: 8888, pageSize: 50, maxPages: 3);

      expect(songs.length, 150);
      expect(client.calls.length, 3);
    });

    test('total 下发且页内混入脏数据（过滤后不足页大小）时，不提前终止翻页', () async {
      // 每页原始 50 条中有 2 条无 hash 被过滤（可播 48 < 50）：
      // 旧的「过滤后条数 < pageSize 即末页」判定会在第 1 页就误停，
      // 只拉到 48 首；total 感知后应翻满 3 页（48+48+28=124）。
      final client = _FakeRankClient([50, 50, 30], total: 124, hashlessPerPage: 2);
      final api = MusicApi(client);

      final songs = await api.rankAudioAll(rankId: 8888, pageSize: 50);

      expect(songs.length, 124);
      expect(client.calls.length, 3);
    });

    test('total 未知时回退页大小启发式（脏数据导致的提前终止仅作已知局限）', () async {
      final client = _FakeRankClient([50, 30], hashlessPerPage: 2);
      final api = MusicApi(client);

      final songs = await api.rankAudioAll(rankId: 8888, pageSize: 50);

      // 第 1 页过滤后 48 < 50 → 按启发式判末页，只请求 1 页。
      expect(songs.length, 48);
      expect(client.calls.length, 1);
    });
  });
}
