import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/services/image_disk_cache.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('shiyin_image_cache_test');
    ImageDiskCache.instance.debugReset();
    ImageDiskCache.instance.debugOverrideDirectory(root);
  });

  tearDown(() {
    ImageDiskCache.instance.debugReset();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  Uint8List bytesOf(int length, {int seed = 0}) =>
      Uint8List.fromList(List<int>.generate(length, (i) => (i + seed) % 251));

  test('文件名取 URL 的 SHA-1：稳定、去重、无路径分隔符', () {
    const url = 'https://imge.kugou.com/stdmusic/240/20230101/a.jpg';
    final name = ImageDiskCache.fileNameFor(url);

    expect(name, hasLength(40));
    expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(name), isTrue);
    // 同 URL 同名，不同 URL 不同名（天然去重）。
    expect(ImageDiskCache.fileNameFor(url), name);
    expect(ImageDiskCache.fileNameFor('$url?x=1'), isNot(name));
    expect(name.contains('/'), isFalse);
  });

  test('未配置上限时不落盘也不命中（磁盘缓存默认关闭）', () async {
    expect(ImageDiskCache.instance.enabled, isFalse);

    await ImageDiskCache.instance.store('https://a/1.jpg', bytesOf(32));

    expect(root.listSync(), isEmpty);
    expect(await ImageDiskCache.instance.lookup('https://a/1.jpg'), isNull);
  });

  test('写入后可命中，内容一致，占用大小可统计且不留残片', () async {
    ImageDiskCache.instance.configure(1024 * 1024);

    final bytes = bytesOf(128, seed: 7);
    await ImageDiskCache.instance.store('https://a/2.jpg', bytes);
    final hit = await ImageDiskCache.instance.lookup('https://a/2.jpg');

    expect(hit, isNotNull);
    expect(await hit!.readAsBytes(), bytes);
    expect(await ImageDiskCache.instance.totalSize(), 128);
    // 落盘走 .part 过渡，完成后不该留下残片。
    expect(
      root
          .listSync()
          .where((entity) => entity.path.endsWith(ImageDiskCache.tempSuffix)),
      isEmpty,
    );
  });

  test('未命中返回 null；单张就超上限时不写盘', () async {
    ImageDiskCache.instance.configure(64);

    expect(await ImageDiskCache.instance.lookup('https://a/miss.jpg'), isNull);

    await ImageDiskCache.instance.store('https://a/big.jpg', bytesOf(128));
    expect(root.listSync(), isEmpty);
  });

  test('空字节不落盘', () async {
    ImageDiskCache.instance.configure(1024);

    await ImageDiskCache.instance.store('https://a/empty.jpg', Uint8List(0));

    expect(root.listSync(), isEmpty);
  });

  test('裁剪按最久未用（mtime）淘汰到 90% 水位', () async {
    ImageDiskCache.instance.configure(400);
    final urls = <String>[for (var i = 0; i < 10; i++) 'https://a/$i.jpg'];
    for (var i = 0; i < urls.length; i++) {
      await ImageDiskCache.instance.store(urls[i], bytesOf(100, seed: i));
    }
    // 10 × 100B = 1000B 超出 400 上限。给每张打上互不相同、按序递增的
    // mtime（0 号最久未用），让淘汰顺序可断言。
    final now = DateTime.now();
    for (var i = 0; i < urls.length; i++) {
      final file = await ImageDiskCache.instance.fileFor(urls[i]);
      await file!.setLastModified(now.subtract(Duration(days: 10 - i)));
    }

    await ImageDiskCache.instance.prune();

    expect(await ImageDiskCache.instance.totalSize(), lessThanOrEqualTo(400));
    // 最久未用的 0 号先被淘汰，最近用过的 9 号必须保留。
    expect(await ImageDiskCache.instance.lookup(urls.first), isNull);
    expect(await ImageDiskCache.instance.lookup(urls.last), isNotNull);
  });

  test('裁剪会清掉残留的 .part 半截文件', () async {
    ImageDiskCache.instance.configure(1024);
    final stale = File('${root.path}/1234${ImageDiskCache.tempSuffix}')
      ..writeAsBytesSync(bytesOf(32));

    await ImageDiskCache.instance.prune();

    expect(stale.existsSync(), isFalse);
  });

  test('清理后目录为空，原 URL 不再命中', () async {
    ImageDiskCache.instance.configure(1024);
    await ImageDiskCache.instance.store('https://a/clear.jpg', bytesOf(64));

    await ImageDiskCache.instance.clear();

    expect(root.listSync(), isEmpty);
    expect(await ImageDiskCache.instance.totalSize(), 0);
    expect(await ImageDiskCache.instance.lookup('https://a/clear.jpg'), isNull);
  });
}
