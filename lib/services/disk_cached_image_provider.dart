import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_disk_cache.dart';

/// 带磁盘缓存的网络图片 Provider。
///
/// 取图顺序：**磁盘 → 网络**（网络成功后异步落盘）。磁盘命中直接解码，省掉
/// 一次网络往返——这是"内存条目被淘汰后封面先变白再逐张回来"的直接解法。
///
/// 与 SDK `NetworkImage` 刻意保持同构，便于原地替换：
/// - 同样用 [SynchronousFuture] 做 key，同样透出 chunkEvents（loadingBuilder
///   的骨架动画依赖它）；
/// - 同样在 debug 下尊重 [debugNetworkImageHttpClientProvider] 与
///   `HttpOverrides`，测试伪造请求的行为不变；
/// - 失败时同样 `imageCache.evict(key)`，不把坏 key 留在缓存里。
///
/// 磁盘缓存不可用时（未 configure / 临时目录拿不到）[ImageDiskCache] 内部会
/// 退化成"永远未命中"，本 Provider 只走网络分支，行为与替换前一致。
class DiskCachedImageProvider extends ImageProvider<DiskCachedImageProvider> {
  const DiskCachedImageProvider(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  // 与 SDK 同款：关闭自动解压，以便信任 Content-Length。
  static final HttpClient _sharedHttpClient = HttpClient()
    ..autoUncompress = false;

  static HttpClient get _httpClient {
    HttpClient? client;
    assert(() {
      if (debugNetworkImageHttpClientProvider != null) {
        client = debugNetworkImageHttpClientProvider!();
      }
      return true;
    }());
    return client ?? _sharedHttpClient;
  }

  @override
  Future<DiskCachedImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<DiskCachedImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    // 所有权移交给 _loadAsync：由它负责在结束时关闭该流。
    final chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode: decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<DiskCachedImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    DiskCachedImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents, {
    required ImageDecoderCallback decode,
  }) async {
    try {
      assert(key == this);

      // 1) 磁盘命中：文件直接交给解码器，不经过 Dart 堆内存。
      final cached = await ImageDiskCache.instance.lookup(key.url);
      if (cached != null) {
        try {
          final buffer = await ui.ImmutableBuffer.fromFilePath(cached.path);
          return await decode(buffer);
        } catch (_) {
          // 文件损坏 / 被外部清理：删条目并按未命中继续走网络。
          await ImageDiskCache.instance.remove(key.url);
        }
      }

      // 2) 网络：拿到字节立即解码，落盘异步进行（不拖慢首帧上屏）。
      final bytes = await _fetch(key.url, chunkEvents);
      unawaited(ImageDiskCache.instance.store(key.url, bytes));
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (error) {
      // 异常路径下 ImageCache 可能还没机会登记 key，给一个微任务再驱逐，
      // 否则坏 key 会长期占据缓存条目（与 SDK 同款处理）。
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(chunkEvents.close());
    }
  }

  Future<Uint8List> _fetch(
    String url,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    final resolved = Uri.base.resolve(url);
    final request = await _httpClient.getUrl(resolved);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      // 网络可能只是临时不可用：排空响应体后抛出，让上层 errorBuilder 兜底，
      // 下次解析仍会重新尝试。
      await response.drain<List<int>>(<int>[]);
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: resolved,
      );
    }
    final bytes = await consolidateHttpClientResponseBytes(
      response,
      onBytesReceived: (int cumulative, int? total) {
        if (!chunkEvents.isClosed) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: cumulative,
              expectedTotalBytes: total,
            ),
          );
        }
      },
    );
    if (bytes.isEmpty) {
      throw Exception('DiskCachedImageProvider: 响应为空: $resolved');
    }
    return bytes;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is DiskCachedImageProvider &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'DiskCachedImageProvider')}'
      '("$url", scale: ${scale.toStringAsFixed(1)})';
}
