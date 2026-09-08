import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/controllers/auth_controller.dart';
import 'package:shiyin_music/models/music_models.dart';
import 'package:shiyin_music/services/music_api.dart';
import 'package:shiyin_music/ui/pages/login_page.dart';

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

class _FakeMusicApi implements MusicApi {
  int qrCodeCalls = 0;
  int checkCalls = 0;
  QrCheckResult Function() checkResult = () =>
      const QrCheckResult(status: 1);

  @override
  Future<QrCodeInfo> getQrCode() async {
    qrCodeCalls++;
    // 1x1 透明 PNG：data URI 形式（与后端 /login/qr/key 返回一致），
    // 尺寸 <10 时反色检测直接返回 false，不依赖图片内容。
    return QrCodeInfo(
      key: 'key_$qrCodeCalls',
      imageUrl:
          'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
  }

  @override
  Future<QrCheckResult> checkQrStatus(String key) async {
    checkCalls++;
    return checkResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeMusicApi> _pumpLoginPage(WidgetTester tester) async {
  final api = _FakeMusicApi();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LoginPage(auth: _FakeAuthController(), api: api),
      ),
    ),
  );
  // 切到扫码登录 tab，触发 _loadQrCode。
  await tester.tap(find.text('扫码登录'));
  await tester.pumpAndSettle();
  expect(find.byType(Image), findsOneWidget);
  return api;
}

void main() {
  testWidgets('状态轮询触发重建时二维码图片流保持不变（不闪）', (tester) async {
    final api = await _pumpLoginPage(tester);

    ImageProvider? providerBefore;
    tester.widget<Image>(find.byType(Image));
    providerBefore = tester.widget<Image>(find.byType(Image)).image;

    // 轮询到「已扫码待确认」：文案变化触发 setState 整页重建，
    // 但二维码 URL 没变，Image provider 必须保持相等（旧实现每次
    // build 重新解码 data URI 产生新 bytes，provider 不等 → 图片流
    // 重新解析 → 二维码每 2 秒白闪）。
    api.checkResult = () => const QrCheckResult(status: 2);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('扫码成功，请在手机上确认'), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      providerBefore,
    );

    // 再轮询回等待扫码：又一次重建，provider 依旧不变。
    api.checkResult = () => const QrCheckResult(status: 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('请使用酷狗音乐App扫码'), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      providerBefore,
    );
  });

  testWidgets('未扫码时 30 秒自动换码，换码后才出现加载过渡', (tester) async {
    final api = await _pumpLoginPage(tester);
    expect(api.qrCodeCalls, 1);

    // 30 秒到点：自动拉新码（key_2），出现加载过渡后展示新码。
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(api.qrCodeCalls, 2);
    expect(find.byType(Image), findsOneWidget);
    // 新码 provider 与旧码不同（data URI 内容相同但按 URL 缓存重解码）。
    expect(api.checkCalls, greaterThan(0));
  });

  testWidgets('已扫码等待确认期间不自动换码（避免作废待确认的扫码）', (tester) async {
    final api = await _pumpLoginPage(tester);
    api.checkResult = () => const QrCheckResult(status: 2);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(api.qrCodeCalls, 1);
    expect(find.text('扫码成功，请在手机上确认'), findsOneWidget);
  });

  testWidgets('二维码过期停止轮询与换码，展示手动刷新按钮', (tester) async {
    final api = await _pumpLoginPage(tester);
    api.checkResult = () => const QrCheckResult(status: 0);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('二维码已过期，点击刷新'), findsOneWidget);
    expect(find.text('刷新二维码'), findsOneWidget);

    // 过期后 30 秒内不再自动换码，等用户手动点刷新。
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(api.qrCodeCalls, 1);

    await tester.tap(find.text('刷新二维码'));
    await tester.pumpAndSettle();
    expect(api.qrCodeCalls, 2);
    expect(find.text('请使用酷狗音乐App扫码'), findsOneWidget);
  });
}
