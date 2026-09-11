import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/config/app_config.dart';
import 'package:shiyin_music/models/app_version.dart';

/// 版本号口径回归锁：semverToCode 必须与 docs/release-process.md 及
/// pubspec `+<code>` 后缀同口径（major*1000000 + minor*1000 + patch）。
/// 曾经分叉为 major*10000 + minor*100 + patch，导致 GitHub 通道
/// （fromGitHubRelease→semverToCode vs 当前 AppConfig.appVersionCode）
/// 同版本恒判"有更新"。
void main() {
  test('semverToCode 与发布流程公式一致：2.5.1 → 2005001', () {
    expect(semverToCode('2.5.1'), 2005001);
    expect(semverToCode('2.4.2'), 2004002);
    expect(semverToCode('v2.5.1'), 2005001);
  });

  test('semverToCode 单调：版本越大 code 越大', () {
    expect(semverToCode('2.4.2'), lessThan(semverToCode('2.5.1')));
    expect(semverToCode('2.5.1'), lessThan(semverToCode('2.5.2')));
    expect(semverToCode('2.5.1'), lessThan(semverToCode('3.0.0')));
  });

  // 旧口径（major*100 + minor*10 + patch）在 minor ≥ 10 时进位冲突：
  // 2.10.0 会得到与 3.0.0 相同的 300。改 3 位小数位后必须单调。
  test('minor 达两位数仍单调（旧口径的进位冲突回归）', () {
    expect(semverToCode('2.9.9'), lessThan(semverToCode('2.10.0')));
    expect(semverToCode('2.10.0'), lessThan(semverToCode('2.11.0')));
    expect(semverToCode('2.10.0'), lessThan(semverToCode('3.0.0')));
    expect(semverToCode('2.10.0'), isNot(semverToCode('3.0.0')));
  });

  // 跨口径升级：新 code 恒大于任何旧 code（旧值最多 3 位），
  // 老用户不会被判成"没有更新"。
  test('新口径 code 恒大于旧口径 code', () {
    int legacyCode(String v) {
      final p = v.replaceFirst(RegExp(r'^v'), '').split('.').map(int.parse).toList();
      return p[0] * 100 + p[1] * 10 + p[2];
    }

    expect(semverToCode('2.5.2'), greaterThan(legacyCode('2.5.1')));
    expect(semverToCode('2.5.1'), greaterThan(legacyCode('2.9.9')));
  });

  // 后两个用例以 AppConfig.appVersion 为基准动态构造 tag，发版升版后
  // 无需同步修改本文件（此前硬编码 v2.5.1/v2.5.2，升版必红）。
  test('同版本 GitHub 信息不判为更新（口径分叉回归）', () {
    final fromGithub = AppVersionInfo.fromGitHubRelease(
      {'tag_name': 'v${AppConfig.appVersion}', 'body': '', 'assets': []},
    );
    expect(
      fromGithub.versionCode,
      normalizedVersionCode(AppConfig.appVersionCode),
    );
    expect(fromGithub.isNewerThanCurrent, isFalse);
  });

  test('高版本 GitHub 仍判为更新', () {
    final parts = AppConfig.appVersion.split('.');
    final bumped = '${parts[0]}.${parts[1]}.${int.parse(parts[2]) + 1}';
    final newer = AppVersionInfo.fromGitHubRelease(
      {'tag_name': 'v$bumped', 'body': '', 'assets': []},
    );
    expect(newer.isNewerThanCurrent, isTrue);
  });
}
