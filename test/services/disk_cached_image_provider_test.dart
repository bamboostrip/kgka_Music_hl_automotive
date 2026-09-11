import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/services/disk_cached_image_provider.dart';
import 'package:shiyin_music/services/image_disk_cache.dart';

/// flutter_test 里 [HttpOverrides.global] 被替换成了打不到本地服务的假实现，
/// 这里用透传覆写拿到真客户端，交给 `debugNetworkImageHttpClientProvider`
/// （Provider 在 debug 下会优先使用它，与 SDK NetworkImage 同款钩子）。
class _RealHttpOverrides extends HttpOverrides {}

/// 1×1 透明 PNG（Flutter 官方测试图 kTransparentImage 同款，引擎必然可解码）。
final Uint8List _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<ImageInfo> _resolveOnce(ImageProvider provider) async {
  final completer = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (ImageInfo info, bool synchronousCall) {
      if (!completer.isCompleted) completer.complete(info);
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completer.isCompleted) completer.completeError(error);
    },
  );
  stream.addListener(listener);
  try {
    return await completer.future;
  } finally {
    stream.removeListener(listener);
  }
}

/// 落盘是 unawaited 的，轮询等它就绪（避免用固定 sleep 造成偶发失败）。
Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('等待条件超时');
}

void main() {
  late Directory root;
  late HttpServer server;
  var requests = 0;
  HttpClient? realClient;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('shiyin_image_provider_test');
    ImageDiskCache.instance.debugReset();
    ImageDiskCache.instance.configure(1024 * 1024);
    ImageDiskCache.instance.debugOverrideDirectory(root);

    requests = 0;
    realClient = HttpOverrides.runWithHttpOverrides(
      HttpClient.new,
      _RealHttpOverrides(),
    );

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        requests++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('image', 'png')
          ..add(_pngBytes);
        await request.response.close();
      }
    }());
  });

  // 绘画调试变量必须在**用例体内**复位：flutter_test 的 _verifyInvariants
  // 在用例体结束后、tearDown 之前执行，放 tearDown 会直接判失败。
  Future<void> withRealHttpClient(Future<void> Function() body) async {
    debugNetworkImageHttpClientProvider = () => realClient!;
    try {
      await body();
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  }

  tearDown(() async {
    debugNetworkImageHttpClientProvider = null;
    realClient?.close(force: true);
    await server.close(force: true);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ImageDiskCache.instance.debugReset();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('磁盘未命中：走网络解码并异步落盘', (tester) async {
    await tester.runAsync(() => withRealHttpClient(() async {
      final url = 'http://127.0.0.1:${server.port}/cover.png';

      expect(await ImageDiskCache.instance.lookup(url), isNull);
      final info = await _resolveOnce(DiskCachedImageProvider(url));

      expect(info.image.width, 1);
      expect(requests, 1);
      await _waitUntil(
        () async => (await ImageDiskCache.instance.lookup(url)) != null,
      );
      expect(await ImageDiskCache.instance.totalSize(), _pngBytes.length);
    }));
  });

  testWidgets('磁盘命中：清掉内存缓存后重新解析不再发起网络请求', (tester) async {
    await tester.runAsync(() => withRealHttpClient(() async {
      final url = 'http://127.0.0.1:${server.port}/cover.png';

      await _resolveOnce(DiskCachedImageProvider(url));
      expect(requests, 1);
      await _waitUntil(
        () async => (await ImageDiskCache.instance.lookup(url)) != null,
      );

      // 只保留磁盘这一层，确保第二次解析无从命中内存。
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final info = await _resolveOnce(DiskCachedImageProvider(url));

      expect(info.image.width, 1);
      expect(requests, 1, reason: '磁盘命中不应该再走网络');
    }));
  });

  testWidgets('磁盘文件损坏：按未命中继续走网络，并清掉坏条目', (tester) async {
    await tester.runAsync(() => withRealHttpClient(() async {
      final url = 'http://127.0.0.1:${server.port}/broken.png';
      final file = await ImageDiskCache.instance.fileFor(url);
      await file!.writeAsBytes(<int>[1, 2, 3, 4, 5, 6, 7, 8]);

      final info = await _resolveOnce(DiskCachedImageProvider(url));

      expect(info.image.width, 1);
      expect(requests, 1);
      // 坏字节被网络结果覆盖为可解码内容（落盘是异步的，轮询等它就绪）。
      await _waitUntil(() async {
        final repaired = await ImageDiskCache.instance.fileFor(url);
        try {
          return repaired != null && await repaired.length() == _pngBytes.length;
        } catch (_) {
          return false;
        }
      });
    }));
  });

  test('Provider 相等性只看 url 与 scale（rebuild 不触发重新解析）', () {
    const a = DiskCachedImageProvider('https://a/1.jpg');
    const b = DiskCachedImageProvider('https://a/1.jpg');
    const c = DiskCachedImageProvider('https://a/2.jpg', scale: 2);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(a.toString(), contains('https://a/1.jpg'));
  });
}
