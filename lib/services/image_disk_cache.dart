import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// 封面（网络图片）磁盘缓存。
///
/// 定位：内存 ImageCache 之外的**第二道保险**。内存条目被 LRU 淘汰后
/// （桌面宽窗一屏铺开的封面数远超上限）或 App 冷启动时，命中磁盘即可直接
/// 解码，不必等一次网络往返——用户看到的是"秒出"，而不是"先白再逐张回来"。
///
/// 设计取舍（与 DownloadController 的播放缓存同一套口径）：
/// - **位置**：`临时目录/<cacheDirName>/<imageCacheDirName>`。放临时目录而不是
///   文档目录，是为了让 Android 在存储紧张时能自动回收——相当于系统帮我们
///   兜底清理，车机最需要这一点；缓存丢了只是下次重新下载，无数据风险。
/// - **命名**：图片 URL 的 SHA-1，天然去重，且不含路径分隔符，无穿越风险。
/// - **淘汰**：按文件 mtime 的 LRU（命中时惰性 touch，1 小时内不重复写元
///   数据）。不做"按日期清理"：听歌行为不规律，按日期清会把命中率砍半，
///   还多出"隔天没启动 → 前前天都留着"这类边界；容量上限 + LRU 才能自适应
///   真实使用强度。
/// - **失败降级**：任何 IO 异常都只记日志并当作"未命中"，绝不影响图片显示。
///   磁盘缓存是优化，不是依赖——它坏了顶多回到今天的行为。
class ImageDiskCache {
  ImageDiskCache._();

  static final ImageDiskCache instance = ImageDiskCache._();

  /// 裁剪水位：淘汰到上限的 90%，避免刚删完又立刻写满、反复触发全量扫描。
  static const _trimRatio = 0.9;

  /// 每写入多少条触发一次裁剪检查（写满 64 张才扫一次目录，成本可忽略）。
  static const _pruneEveryWrites = 64;

  /// 命中后至少间隔这么久才回写一次 mtime，避免每张图都产生一次元数据写。
  static const _touchInterval = Duration(hours: 1);

  /// 落盘临时后缀：写入过程中被杀进程不会留下半截文件被当成命中。
  /// 公开给单测断言"不留残片"。
  static const tempSuffix = '.part';

  int _maxBytes = 0;
  int _writesSincePrune = 0;
  bool _disabled = false;
  Directory? _dir;
  Future<void>? _pruneFuture;

  /// 是否启用（上限 > 0 且目录可用）。未调用 [configure] 时为 false。
  bool get enabled => !_disabled && _maxBytes > 0;

  /// 当前上限（字节，0 表示关闭）。
  int get maxBytes => _maxBytes;

  /// 配置上限。**同步、不做任何 IO**：可在启动早期调用，目录按需惰性创建。
  void configure(int maxBytes) {
    _maxBytes = maxBytes;
    if (maxBytes <= 0) _disabled = true;
  }

  /// 仅供测试：直接指定缓存目录，绕过 path_provider（单测环境拿不到临时目录）。
  @visibleForTesting
  void debugOverrideDirectory(Directory? dir) {
    _dir = dir;
  }

  /// 仅供测试：重置上限/禁用标记，避免用例之间互相污染。
  @visibleForTesting
  void debugReset() {
    _maxBytes = 0;
    _disabled = false;
    _dir = null;
    _writesSincePrune = 0;
  }

  /// 磁盘文件名：URL 的 SHA-1。
  static String fileNameFor(String url) =>
      sha1.convert(utf8.encode(url)).toString();

  /// 某 URL 对应的磁盘文件（可能尚不存在）；缓存关闭时返回 null。
  Future<File?> fileFor(String url) async {
    final dir = await _ensureDir();
    if (dir == null) return null;
    return File('${dir.path}/${fileNameFor(url)}');
  }

  Future<Directory?> _ensureDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    if (!enabled) return null;
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(
        '${base.path}/${AppConfig.cacheDirName}/${AppConfig.imageCacheDirName}',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
      return dir;
    } catch (error) {
      // 单测骨架 / 极简环境拿不到临时目录：永久关闭磁盘缓存，图片照常走网络。
      debugPrint('ImageDiskCache: 目录不可用，已关闭磁盘缓存（不影响图片显示）: $error');
      _disabled = true;
      return null;
    }
  }

  /// 命中返回磁盘文件（并惰性刷新 mtime 做 LRU），未命中返回 null。
  Future<File?> lookup(String url) async {
    // 关闭状态下不碰磁盘（与 store/prune 同一口径），避免"配成 0 还在读旧文件"。
    if (!enabled) return null;
    try {
      final file = await fileFor(url);
      if (file == null) return null;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        if (stat.type != FileSystemEntityType.notFound) {
          unawaited(remove(url));
        }
        return null;
      }
      final now = DateTime.now();
      if (now.difference(stat.modified) > _touchInterval) {
        unawaited(file.setLastModified(now).catchError((Object _) => file));
      }
      return file;
    } catch (_) {
      // 磁盘异常按未命中处理，交给网络路径兜底。
      return null;
    }
  }

  /// 落盘（失败静默）。先写 `.part` 再 rename，保证读到的永远是完整文件。
  Future<void> store(String url, Uint8List bytes) async {
    if (bytes.isEmpty || !enabled) return;
    // 单张就超过总上限时不落盘，否则会立刻把自己挤出去，白写一次。
    if (bytes.length > _maxBytes) return;
    try {
      final file = await fileFor(url);
      if (file == null) return;
      final temp = File('${file.path}$tempSuffix');
      await temp.writeAsBytes(bytes, flush: false);
      await temp.rename(file.path);
      _writesSincePrune++;
      if (_writesSincePrune >= _pruneEveryWrites) {
        _writesSincePrune = 0;
        unawaited(prune());
      }
    } catch (_) {
      // 磁盘满/权限不足等：不影响本次显示，下次按未命中重来。
    }
  }

  /// 删除单条（读盘损坏或网络重取时用）。
  Future<void> remove(String url) async {
    try {
      final file = await fileFor(url);
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 当前占用字节数（顺带把读不到的条目剔除，不触发网络请求）。
  Future<int> totalSize() async {
    try {
      final dir = await _ensureDir();
      if (dir == null) return 0;
      var total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          total += (await entity.stat()).size;
        } catch (_) {}
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 按 mtime LRU 裁剪到上限的 90%。同一时刻只跑一次，重复调用复用同一 Future。
  Future<void> prune() {
    final running = _pruneFuture;
    if (running != null) return running;
    final future = _prune();
    _pruneFuture = future;
    return future.whenComplete(() {
      _pruneFuture = null;
    });
  }

  Future<void> _prune() async {
    if (!enabled) return;
    try {
      final dir = await _ensureDir();
      if (dir == null) return;
      final entries = <({File file, int size, DateTime usedAt})>[];
      var total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        // 残留的半截文件直接清掉（上次写入被打断）。
        if (entity.path.endsWith(tempSuffix)) {
          try {
            await entity.delete();
          } catch (_) {}
          continue;
        }
        try {
          final stat = await entity.stat();
          if (stat.size <= 0) {
            await entity.delete();
            continue;
          }
          entries.add((file: entity, size: stat.size, usedAt: stat.modified));
          total += stat.size;
        } catch (_) {}
      }
      if (total <= _maxBytes) return;
      final target = (_maxBytes * _trimRatio).round();
      entries.sort((a, b) => a.usedAt.compareTo(b.usedAt));
      for (final entry in entries) {
        if (total <= target) break;
        try {
          await entry.file.delete();
          total -= entry.size;
        } catch (_) {}
      }
    } catch (error) {
      debugPrint('ImageDiskCache: 裁剪失败（已忽略）: $error');
    }
  }

  /// 清空封面磁盘缓存（设置页手动清理入口）。
  Future<void> clear() async {
    try {
      final dir = await _ensureDir();
      if (dir == null) return;
      await for (final entity in dir.list(followLinks: false)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (error) {
      debugPrint('ImageDiskCache: 清理失败: $error');
    }
  }
}
