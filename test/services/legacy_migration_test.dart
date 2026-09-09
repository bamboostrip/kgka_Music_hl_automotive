import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiyin_music/services/legacy_migration.dart';

/// LegacyMigration.run() 中的磁盘目录部分依赖 path_provider 平台通道，
/// 单测环境不可用（内部 try/catch 自动跳过），此处覆盖可纯 Dart 验证的
/// SharedPreferences 键迁移与索引路径重写逻辑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('精确键全部复制到 shiyin_* 并删除旧键', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ka_music_token', 'tok-123');
    await prefs.setString('ka_music_t1', 't1-456');
    await prefs.setString('ka_music_session_id', 'sid');
    await prefs.setString('ka_music_user_id', 'uid');
    await prefs.setStringList('ka_music_liked_hashes', ['h1', 'h2']);

    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includeWindowsDataDirs: false);

    expect(prefs.getString('shiyin_token'), 'tok-123');
    expect(prefs.getString('shiyin_t1'), 't1-456');
    expect(prefs.getString('shiyin_session_id'), 'sid');
    expect(prefs.getString('shiyin_user_id'), 'uid');
    expect(prefs.getStringList('shiyin_liked_hashes'), ['h1', 'h2']);
    expect(prefs.getKeys().where((k) => k.startsWith('ka_music')), isEmpty);
  });

  test('动态前缀键（用户歌单缓存）逐键改名', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ka_music_cached_playlists_u1', 'A');
    await prefs.setInt('ka_music_playlist_empty_count_u1', 2);

    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includeWindowsDataDirs: false);

    expect(prefs.getString('shiyin_cached_playlists_u1'), 'A');
    expect(prefs.getInt('shiyin_playlist_empty_count_u1'), 2);
    expect(prefs.containsKey('ka_music_cached_playlists_u1'), isFalse);
    expect(prefs.containsKey('ka_music_playlist_empty_count_u1'), isFalse);
  });

  test('新键已存在时以新键为准，仅清理旧键', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ka_music_token', 'old');
    await prefs.setString('shiyin_token', 'new');

    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includeWindowsDataDirs: false);

    expect(prefs.getString('shiyin_token'), 'new');
    expect(prefs.containsKey('ka_music_token'), isFalse);
  });

  test('重复执行幂等（迁移后的键不受影响）', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ka_music_token', 'tok');

    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includeWindowsDataDirs: false);
    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includeWindowsDataDirs: false);

    expect(prefs.getString('shiyin_token'), 'tok');
  });

  test('索引仅复制不重写：宿主目录不可达时保留旧绝对路径', () async {
    final prefs = await SharedPreferences.getInstance();
    final index = jsonEncode([
      {
        'filePath': '/storage/emulated/0/Android/data/pkg/files'
            '/ka_music_downloads/a.mp3',
      },
    ]);
    await prefs.setString('ka_music_downloads_index', index);

    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includeWindowsDataDirs: false);

    // 单测环境 path_provider 不可用 → 目录解析失败被跳过；
    // 但键已复制。旧目录"不存在或已迁移"时索引重写为预期行为，
    // 这里至少保证键迁移不损坏 JSON 值。
    final migrated = prefs.getString('shiyin_downloads_index');
    expect(migrated, isNotNull);
    final decoded = jsonDecode(migrated!) as List;
    final path = (decoded.first as Map)['filePath'] as String;
    expect(path, contains('ka_music_downloads')); // 目录未移动则不重写
  });
}
