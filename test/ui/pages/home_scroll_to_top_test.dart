import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/controllers/auth_controller.dart';
import 'package:shiyin_music/controllers/download_controller.dart';
import 'package:shiyin_music/controllers/local_music_controller.dart';
import 'package:shiyin_music/controllers/player_controller.dart';
import 'package:shiyin_music/controllers/theme_controller.dart';
import 'package:shiyin_music/models/music_models.dart';
import 'package:shiyin_music/services/cache_service.dart';
import 'package:shiyin_music/services/music_api.dart';
import 'package:shiyin_music/ui/form_factor.dart';
import 'package:shiyin_music/ui/pages/app_shell.dart';

class _FakeMusicApi implements MusicApi {
  int dailyRecommendCalls = 0;
  int recommendedPlaylistsCalls = 0;
  int topSongsCalls = 0;

  List<Song> dailySongs = const [];
  List<Song> topSongsData = const [];
  List<PlaylistSummary> playlists = const [];
  List<Song> playlistSongsData = const [];

  @override
  Future<List<Song>> playlistSongs(
    String id, {
    int page = 1,
    int pageSize = 30,
    bool fetchAll = false,
  }) async {
    return playlistSongsData;
  }

  @override
  Future<DailyRecommend> dailyRecommend() async {
    dailyRecommendCalls++;
    return DailyRecommend(title: '每日推荐', songs: dailySongs);
  }

  @override
  Future<List<PlaylistSummary>> recommendedPlaylists({
    int categoryId = 0,
    int page = 1,
  }) async {
    recommendedPlaylistsCalls++;
    return playlists;
  }

  @override
  Future<List<Song>> topSongs({int type = 21608, int page = 1}) async {
    topSongsCalls++;
    return topSongsData;
  }

  @override
  Future<List<RankCategory>> rankList({int withSong = 0}) async => const [];

  @override
  Future<List<Song>> newSongs({int rankId = 0, int page = 1}) async =>
      const [];

  @override
  Future<List<FmStation>> fmRecommendedStations() async => const [];

  @override
  Future<List<FmClassGroup>> fmClassGroups() async => const [];

  @override
  Future<Map<String, FmImage>> fmImages(List<String> fmids) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayerController extends ChangeNotifier
    implements PlayerController {
  @override
  Song? currentSong;

  @override
  bool isPlaying = false;

  @override
  bool isPreparing = false;

  @override
  Duration position = Duration.zero;

  @override
  Duration duration = Duration.zero;

  @override
  String? errorMessage;

  @override
  List<Song> queue = [];

  @override
  bool autoPlayOnStartupEnabled = false;

  @override
  bool hasRestoredPlaybackState = false;

  @override
  final ValueNotifier<Duration> positionListenable =
      ValueNotifier(Duration.zero);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthController extends ChangeNotifier implements AuthController {
  @override
  bool isRestoring = false;

  @override
  bool get isLoggedIn => true;

  @override
  bool isLiked(Song song) => false;

  @override
  Future<void> toggleLike(Song song) async {}

  @override
  List<PlaylistSummary> get createdPlaylists => const [];

  @override
  List<PlaylistSummary> get collectedPlaylists => const [];

  @override
  List<PlaylistSummary> get collectedAlbums => const [];

  @override
  PlaylistSummary? get likedPlaylist => null;

  @override
  int get likedCount => 0;

  @override
  UserProfile? get profile => null;

  @override
  UserVipInfo? get vipInfo => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache implements CacheService {
  @override
  Future<CacheResult<T>?> read<T>(
    String key, {
    required T Function(Map<String, dynamic> json) decode,
    Duration ttl = const Duration(hours: 24),
  }) async =>
      null;

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDownloadController extends ChangeNotifier
    implements DownloadController {
  @override
  List<Song> get downloadedSongs => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalMusicController extends ChangeNotifier
    implements LocalMusicController {
  @override
  List<Song> get songs => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Song _song(int i) => Song(
      id: 'id_$i',
      title: '新歌$i',
      artist: '歌手$i',
      hash: 'hash_$i',
    );

void main() {
  ThemeController();

  Future<_FakeMusicApi> pumpAppShell(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    debugDesktopFormFactorOverride = false;
    addTearDown(() => debugDesktopFormFactorOverride = null);

    appShellNow = () => tester.binding.clock.now();
    addTearDown(() => appShellNow = DateTime.now);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeMusicApi()
      ..dailySongs = List.generate(10, (i) => _song(i))
      ..topSongsData = List.generate(12, (i) => _song(100 + i))
      ..playlists = List.generate(
        8,
        (i) => PlaylistSummary(id: 'pl_$i', title: '歌单$i', coverUrl: null),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          api: api,
          auth: _FakeAuthController(),
          player: _FakePlayerController(),
          cache: _FakeCache(),
          theme: ThemeController(),
          downloads: _FakeDownloadController(),
          localMusic: _FakeLocalMusicController(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  ScrollableState getVerticalScrollable(WidgetTester tester) {
    final scrollables =
        tester.stateList<ScrollableState>(find.byType(Scrollable));
    return scrollables.firstWhere(
      (s) =>
          s.axisDirection == AxisDirection.down ||
          s.axisDirection == AxisDirection.up,
    );
  }

  testWidgets('滚动首页后双击底部「首页」，平滑回顶并展开搜索栏且触发刷新 API', (tester) async {
    final api = await pumpAppShell(tester);
    final initialDailyCalls = api.dailyRecommendCalls;
    expect(initialDailyCalls, greaterThanOrEqualTo(1));

    final searchBarTextFinder = find.text('搜索歌曲、歌手、专辑');
    expect(searchBarTextFinder, findsOneWidget);

    // Initial search opacity should be 1.0
    final initialOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: searchBarTextFinder,
        matching: find.byType(Opacity),
      ).first,
    );
    expect(initialOpacity.opacity, 1.0);

    final scrollable = getVerticalScrollable(tester);
    expect(scrollable.position.pixels, 0.0);

    // Scroll down 250 pixels
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(40.0));
    final collapsedOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: searchBarTextFinder,
        matching: find.byType(Opacity),
      ).first,
    );
    expect(collapsedOpacity.opacity, 0.0);

    // Double tap '首页' item on bottom bar
    final homeTabFinder = find.text('首页');
    expect(homeTabFinder, findsOneWidget);

    await tester.tap(homeTabFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(homeTabFinder);
    await tester.pumpAndSettle();

    // Verify it smoothly scrolled back to top
    expect(scrollable.position.pixels, 0.0);

    // Verify search bar is expanded again
    final restoredOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: searchBarTextFinder,
        matching: find.byType(Opacity),
      ).first,
    );
    expect(restoredOpacity.opacity, 1.0);

    // Verify refresh API was called
    expect(api.dailyRecommendCalls, greaterThan(initialDailyCalls));
  });

  testWidgets('直接双击底部「首页」，触发刷新 API', (tester) async {
    final api = await pumpAppShell(tester);
    final initialDailyCalls = api.dailyRecommendCalls;

    final homeTabFinder = find.text('首页');
    await tester.tap(homeTabFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(homeTabFinder);
    await tester.pumpAndSettle();

    expect(api.dailyRecommendCalls, greaterThan(initialDailyCalls));
  });

  testWidgets('在「我的」页双击「首页」，切换回首页并触发回顶刷新', (tester) async {
    final api = await pumpAppShell(tester);
    final initialDailyCalls = api.dailyRecommendCalls;

    // Switch to '我的' tab
    final myTabFinder = find.text('我的');
    await tester.tap(myTabFinder);
    await tester.pumpAndSettle();

    // Now double tap '首页' tab
    final homeTabFinder = find.text('首页');
    await tester.tap(homeTabFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(homeTabFinder);
    await tester.pumpAndSettle();

    // HomePage is displayed again and refreshed
    expect(find.text('搜索歌曲、歌手、专辑'), findsOneWidget);
    expect(api.dailyRecommendCalls, greaterThan(initialDailyCalls));
  });

  testWidgets('单击「首页」不触发刷新', (tester) async {
    final api = await pumpAppShell(tester);
    final initialDailyCalls = api.dailyRecommendCalls;

    final homeTabFinder = find.text('首页');
    await tester.tap(homeTabFinder);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Refresh API should NOT be called on single tap
    expect(api.dailyRecommendCalls, initialDailyCalls);
  });

  testWidgets('两次点击间隔超过 350ms 时不触发刷新', (tester) async {
    final api = await pumpAppShell(tester);
    final initialDailyCalls = api.dailyRecommendCalls;

    final homeTabFinder = find.text('首页');
    await tester.tap(homeTabFinder);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.tap(homeTabFinder);
    await tester.pumpAndSettle();

    expect(api.dailyRecommendCalls, initialDailyCalls);
  });

  testWidgets('宽屏 NavigationRail 下双击「首页」触发刷新 API', (tester) async {
    final api = await pumpAppShell(tester, size: const Size(800, 1000));
    final initialDailyCalls = api.dailyRecommendCalls;

    expect(find.byType(NavigationRail), findsOneWidget);
    final homeTabFinder = find.text('首页');
    expect(homeTabFinder, findsOneWidget);

    await tester.tap(homeTabFinder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(homeTabFinder);
    await tester.pumpAndSettle();

    expect(api.dailyRecommendCalls, greaterThan(initialDailyCalls));
  });
}
