import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 旧标识（KA Music / kgka 时代）→ 时音命名的一次性迁移。
///
/// 覆盖三类用户数据，保证改名对老用户零感知：
/// 1. SharedPreferences 键：`ka_music_*` → `shiyin_*`（登录态、收藏、
///    歌单缓存、下载/播放缓存索引）；
/// 2. 磁盘目录：`ka_music_downloads` / `ka_music_play_cache` →
///    `shiyin_*`（父目录不变，整目录 rename；随后重写索引里的绝对路径）；
/// 3. Windows 应用数据目录：`%APPDATA%\com.example\时音` →
///    `%APPDATA%\shiyin\时音`（VERSIONINFO CompanyName 改名的连带迁移，
///    Rust 引擎的 kg_session.json 随目录整体搬移）。
///
/// 设计约束：
/// - 任一步失败都不得阻断启动：全程 try/catch，失败只留日志；
/// - 幂等：旧键复制成功后即删除，旧目录移动后不存在，重复执行为 no-op；
/// - 目录移动失败（权限/新旧目录都非空）时**不重写索引**——旧绝对路径
///   仍然有效，最坏情况是"新旧目录并存"，绝不丢下载记录。
///
/// Android 通知渠道 ID 的迁移在原生侧 MusicApplication.kt 完成
/// （系统渠道 API 无法从 Dart 删除）；MethodChannel 名纯内部通信无数据
/// 迁移需求，双端同步改名即可。
class LegacyMigration {
  const LegacyMigration._();

  /// 旧下载目录名（AppConfig.downloadDirName 改名前的值）。
  static const _oldDownloadsDirName = 'ka_music_downloads';
  /// 旧播放缓存目录名（AppConfig.playCacheDirName 改名前的值）。
  static const _oldPlayCacheDirName = 'ka_music_play_cache';

  /// 精确键映射（旧 → 新）。
  static const _exactKeys = <String, String>{
    'ka_music_token': 'shiyin_token',
    'ka_music_t1': 'shiyin_t1',
    'ka_music_session_id': 'shiyin_session_id',
    'ka_music_user_id': 'shiyin_user_id',
    'ka_music_liked_hashes': 'shiyin_liked_hashes',
    'ka_music_cached_playlists': 'shiyin_cached_playlists',
    'ka_music_playlist_empty_count': 'shiyin_playlist_empty_count',
    'ka_music_downloads_index': 'shiyin_downloads_index',
    'ka_music_play_cache_index': 'shiyin_play_cache_index',
  };

  /// 动态后缀键的前缀映射（如 `ka_music_cached_playlists_<userId>`）。
  /// 精确键与动态前缀共用同一命名时，先按精确表复制，再扫前缀兜底
  /// 残余的动态键，两遍互不冲突（精确表已删旧键）。
  static const _prefixPairs = <(String, String)>[
    ('ka_music_cached_playlists', 'shiyin_cached_playlists'),
    ('ka_music_playlist_empty_count', 'shiyin_playlist_empty_count'),
  ];

  /// 在 runApp 之前（且必须先于 RustApiClient.getInstance——它拿到的是
  /// Windows 支持目录，见 _migrateWindowsCompanyDirs）调用一次。
  ///
  /// [includeWindowsDataDirs] 仅供单元测试关闭真实用户目录搬移
  /// （flutter test 运行在开发者真机上，Platform.environment 指向真实
  /// %APPDATA%），生产路径一律保持默认 true。
  static Future<void> run({
    bool includeWindowsDataDirs = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _migratePrefKeys(prefs);
      await _migrateDownloadsDir(prefs);
      await _migratePlayCacheDir(prefs);
      if (includeWindowsDataDirs) {
        await _migrateWindowsCompanyDirs();
      }
    } catch (error, stack) {
      // 迁移失败不阻断启动：最坏是老键继续被读（改名后新键无值 →
      // 等同未登录/无缓存），下次启动还会再试。
      debugPrint('[时音][migration] 旧标识迁移异常（已跳过）: $error\n$stack');
    }
  }

  // ===== SharedPreferences 键 =====

  static Future<void> _migratePrefKeys(SharedPreferences prefs) async {
    final keys = prefs.getKeys();
    // 1. 精确映射
    for (final entry in _exactKeys.entries) {
      if (keys.contains(entry.key)) {
        await _copyPref(prefs, entry.key, entry.value);
      }
    }
    // 2. 动态前缀键（getKeys 是快照，逐对前缀扫描）
    for (final (oldPrefix, newPrefix) in _prefixPairs) {
      for (final key in keys) {
        if (key.startsWith(oldPrefix) && !_exactKeys.containsKey(key)) {
          await _copyPref(prefs, key, newPrefix + key.substring(oldPrefix.length));
        }
      }
    }
  }

  static Future<void> _copyPref(
    SharedPreferences prefs,
    String from,
    String to,
  ) async {
    final value = prefs.get(from);
    if (value == null) return;
    if (prefs.containsKey(to)) {
      // 新键已有值（迁移中断后重跑等）：以新键为准，清旧键即可。
      await prefs.remove(from);
      return;
    }
    final ok = switch (value) {
      final String s => await prefs.setString(to, s),
      final bool b => await prefs.setBool(to, b),
      final int i => await prefs.setInt(to, i),
      final double d => await prefs.setDouble(to, d),
      final List<String> l => await prefs.setStringList(to, l),
      _ => false,
    };
    if (ok) {
      await prefs.remove(from);
    } else {
      debugPrint('[时音][migration] 迁移键 $from → $to 写入失败，保留旧键');
    }
  }

  // ===== 磁盘目录 + 索引内绝对路径 =====

  static Future<void> _migrateDownloadsDir(SharedPreferences prefs) async {
    final parent = await _downloadsParentDir();
    if (parent == null) return;
    await _migrateDir(
      prefs,
      oldPath: '${parent.path}${Platform.pathSeparator}$_oldDownloadsDirName',
      newPath: '${parent.path}${Platform.pathSeparator}${AppConfig.downloadDirName}',
      indexKey: 'shiyin_downloads_index',
      oldName: _oldDownloadsDirName,
      newName: AppConfig.downloadDirName,
    );
  }

  static Future<void> _migratePlayCacheDir(SharedPreferences prefs) async {
    Directory? base;
    try {
      base = await getTemporaryDirectory();
    } catch (_) {}
    if (base == null) return;
    await _migrateDir(
      prefs,
      oldPath: '${base.path}${Platform.pathSeparator}$_oldPlayCacheDirName',
      newPath: '${base.path}${Platform.pathSeparator}${AppConfig.playCacheDirName}',
      indexKey: 'shiyin_play_cache_index',
      oldName: _oldPlayCacheDirName,
      newName: AppConfig.playCacheDirName,
    );
  }

  /// 镜像 DownloadService.downloadDir() 的父目录解析（Android 专属外部
  /// 目录 → 桌面 Downloads → 文档目录兜底），只到父级，不拼接子目录。
  static Future<Directory?> _downloadsParentDir() async {
    try {
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectory();
        if (external != null) return external;
        return await getApplicationDocumentsDirectory();
      }
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) return downloads;
      }
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  /// 整目录 rename 迁移旧目录，成功后重写索引 JSON 字符串里的目录名段。
  static Future<void> _migrateDir(
    SharedPreferences prefs, {
    required String oldPath,
    required String newPath,
    required String indexKey,
    required String oldName,
    required String newName,
  }) async {
    final oldDir = Directory(oldPath);
    final newDir = Directory(newPath);
    if (!await oldDir.exists()) {
      // 旧目录不存在：全新安装，或目录已迁移但索引重写曾在中断中失败——
      // 仍尝试重写一次（幂等 replaceAll，对已重写值无副作用）。
      await _rewriteIndex(prefs, indexKey, oldName, newName);
      return;
    }
    if (await newDir.exists() && await _directoryHasEntries(newDir)) {
      // 新旧目录都非空：不做合并（避免同名覆盖），旧索引路径继续有效，
      // 新下载自然落到新目录。
      debugPrint('[时音][migration] $oldName 与 $newName 并存，跳过目录合并');
      return;
    }
    try {
      // rename 到已存在的空目录在 POSIX 会 ENOTEMPTY/EEXIST，Windows 同理
      // 要求目标不存在；新目录若是本次 path_provider 刚建的空壳，先删。
      if (await newDir.exists()) await newDir.delete();
      await oldDir.rename(newPath);
      await _rewriteIndex(prefs, indexKey, oldName, newName);
      debugPrint('[时音][migration] 已迁移目录 $oldName → $newName');
    } catch (error) {
      // 跨卷 rename 等失败：保持旧路径可用，不重写索引。
      debugPrint('[时音][migration] 目录 $oldName 迁移失败（保留旧路径）: $error');
    }
  }

  static Future<bool> _directoryHasEntries(Directory dir) async {
    try {
      return dir.listSync(recursive: false, followLinks: false).isNotEmpty;
    } catch (_) {
      // 列不出来按"非空"保守处理，不动用户数据。
      return true;
    }
  }

  static Future<void> _rewriteIndex(
    SharedPreferences prefs,
    String indexKey,
    String oldName,
    String newName,
  ) async {
    final raw = prefs.getString(indexKey);
    if (raw == null || !raw.contains(oldName)) return;
    await prefs.setString(
      indexKey,
      raw.replaceAll(oldName, newName),
    );
  }

  // ===== Windows 应用数据目录（CompanyName 改名连带） =====

  /// VERSIONINFO CompanyName 从 com.example 改为 shiyin 后，
  /// path_provider_windows 的 support/cache 目录变为
  /// `%APPDATA%\shiyin\时音` / `%LOCALAPPDATA%\shiyin\时音`。
  /// 整目录搬移（内含 Rust 引擎 kg_session.json），登录态不丢。
  static Future<void> _migrateWindowsCompanyDirs() async {
    if (!Platform.isWindows) return;
    final env = Platform.environment;
    final moves = <(String, String)>[
      ('APPDATA', 'Roaming'),
      ('LOCALAPPDATA', 'Local'),
    ];
    for (final (envKey, label) in moves) {
      final root = env[envKey];
      if (root == null || root.isEmpty) continue;
      final oldDir = Directory(
        '$root\\com.example\\${AppConfig.appName}',
      );
      final newDir = Directory('$root\\shiyin\\${AppConfig.appName}');
      if (!await oldDir.exists()) continue;
      try {
        if (await newDir.exists()) {
          // 新目录已存在（迁移中断路径）：不做合并。
          continue;
        }
        // rename 要求目标不存在但父级存在：先确保 %…%\shiyin 父目录就绪。
        final parent = Directory('$root\\shiyin');
        if (!await parent.exists()) await parent.create(recursive: true);
        await oldDir.rename(newDir.path);
        debugPrint('[时音][migration] 已迁移 $label 应用数据目录 com.example → shiyin');
      } catch (error) {
        debugPrint('[时音][migration] $label 应用数据目录迁移失败: $error');
      }
    }
  }
}
