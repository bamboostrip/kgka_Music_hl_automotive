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
    await LegacyMigration.run(includePlatformDataDirs: false);

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
    await LegacyMigration.run(includePlatformDataDirs: false);

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
    await LegacyMigration.run(includePlatformDataDirs: false);

    expect(prefs.getString('shiyin_token'), 'new');
    expect(prefs.containsKey('ka_music_token'), isFalse);
  });

  test('重复执行幂等（迁移后的键不受影响）', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ka_music_token', 'tok');

    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includePlatformDataDirs: false);
    // flutter test 跑在开发者真机：必须关闭真实 %APPDATA% 目录搬移
    await LegacyMigration.run(includePlatformDataDirs: false);

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
    await LegacyMigration.run(includePlatformDataDirs: false);

    // 单测环境 path_provider 不可用 → 目录解析失败被跳过；
    // 但键已复制。旧目录"不存在或已迁移"时索引重写为预期行为，
    // 这里至少保证键迁移不损坏 JSON 值。
    final migrated = prefs.getString('shiyin_downloads_index');
    expect(migrated, isNotNull);
    final decoded = jsonDecode(migrated!) as List;
    final path = (decoded.first as Map)['filePath'] as String;
    expect(path, contains('ka_music_downloads')); // 目录未移动则不重写
  });

  group('平台数据目录路径计算', () {
    test('Windows：com.example\\时音 → shiyin\\时音（Roaming/Local 同构）', () {
      final (roamingOld, roamingNew) = LegacyMigration.windowsCompanyDirMoves(
        r'C:\Users\u\AppData\Roaming',
        '时音',
      );
      expect(roamingOld, r'C:\Users\u\AppData\Roaming\com.example\时音');
      expect(roamingNew, r'C:\Users\u\AppData\Roaming\shiyin\时音');

      final (localOld, localNew) = LegacyMigration.windowsCompanyDirMoves(
        r'C:\Users\u\AppData\Local',
        '时音',
      );
      expect(localOld, r'C:\Users\u\AppData\Local\com.example\时音');
      expect(localNew, r'C:\Users\u\AppData\Local\shiyin\时音');
    });

    test('Linux：XDG_DATA_HOME 优先，旧 app id 与旧二进制名双候选', () {
      final moves = LegacyMigration.linuxDataDirMoves(
        '/custom/data',
        '/home/u',
      );
      expect(moves, hasLength(2));
      expect(moves[0], ('/custom/data/com.hoilai.mm.music', '/custom/data/top.famlife.shiyin'));
      expect(moves[1], ('/custom/data/kgka_music_hl', '/custom/data/top.famlife.shiyin'));

      final fallback = LegacyMigration.linuxDataDirMoves(null, '/home/u');
      expect(fallback[0].$1, '/home/u/.local/share/com.hoilai.mm.music');
      expect(fallback[0].$2, '/home/u/.local/share/top.famlife.shiyin');

      // HOME 与 XDG_DATA_HOME 都缺失：无迁移可做。
      expect(LegacyMigration.linuxDataDirMoves(null, null), isEmpty);
      expect(LegacyMigration.linuxDataDirMoves('', ''), isEmpty);
    });

    test('macOS：容器 / Application Support / Preferences plist 三路径', () {
      final moves = LegacyMigration.macosDataDirMoves('/Users/u');
      expect(moves['containers'], '/Users/u/Library/Containers/com.example.kgkaMusicHl');
      expect(moves['containersNew'], '/Users/u/Library/Containers/top.famlife.shiyin');
      expect(moves['support'], '/Users/u/Library/Application Support/com.example.kgkaMusicHl');
      expect(moves['supportNew'], '/Users/u/Library/Application Support/top.famlife.shiyin');
      expect(moves['prefs'], '/Users/u/Library/Preferences/com.example.kgkaMusicHl.plist');
      expect(moves['prefsNew'], '/Users/u/Library/Preferences/top.famlife.shiyin.plist');
    });
  });
}
