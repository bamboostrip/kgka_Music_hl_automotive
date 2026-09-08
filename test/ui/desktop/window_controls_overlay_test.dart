import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/controllers/auth_controller.dart';
import 'package:shiyin_music/controllers/player_controller.dart';
import 'package:shiyin_music/models/music_models.dart';
import 'package:shiyin_music/services/music_api.dart';
import 'package:shiyin_music/ui/desktop/desktop_window_controls.dart';
import 'package:shiyin_music/ui/form_factor.dart';
import 'package:shiyin_music/ui/pages/login_page.dart';
import 'package:shiyin_music/ui/pages/player_page.dart';

class _FakeMusicApi implements MusicApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayerController extends ChangeNotifier
    implements PlayerController {
  @override
  Song? currentSong;

  @override
  List<Song> queue = const [];

  @override
  Duration duration = Duration.zero;

  @override
  final ValueNotifier<Duration> positionListenable =
      ValueNotifier<Duration>(Duration.zero);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthController extends ChangeNotifier implements AuthController {
  @override
  bool isRestoring = false;
  @override
  bool get isLoggedIn => false;
  @override
  String? errorMessage;
  @override
  bool isLoading = false;
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

void main() {
  testWidgets('桌面形态登录页叠加窗口控制浮层，移动端不叠加', (tester) async {
    debugDesktopFormFactorOverride = true;
    addTearDown(() => debugDesktopFormFactorOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: _FakeAuthController(), api: _FakeMusicApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 无边框窗口没有系统标题栏，登录页必须自带拖拽条 + 窗口三键，
    // 否则窗口拖不动也关不掉。
    expect(find.byType(DesktopWindowControlsOverlay), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.byTooltip('最小化'), findsOneWidget);

    // 移动端形态不叠加（有系统状态栏/导航，无需窗口控制）。
    debugDesktopFormFactorOverride = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginPage(auth: _FakeAuthController(), api: _FakeMusicApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopWindowControlsOverlay), findsNothing);
  });

  testWidgets('桌面形态播放页（整屏路由）叠加窗口控制浮层', (tester) async {
    debugDesktopFormFactorOverride = true;
    addTearDown(() => debugDesktopFormFactorOverride = null);

    // 空态分支即可验证：浮层包在整个 PlayerPage 外层，与有无歌曲无关。
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          player: _FakePlayerController(),
          auth: _FakeAuthController(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopWindowControlsOverlay), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);

    debugDesktopFormFactorOverride = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          player: _FakePlayerController(),
          auth: _FakeAuthController(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopWindowControlsOverlay), findsNothing);
  });
}
