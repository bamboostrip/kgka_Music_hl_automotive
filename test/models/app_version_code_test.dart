import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/config/app_config.dart';
import 'package:shiyin_music/models/app_version.dart';

/// 版本号口径回归锁：semverToCode 必须与 docs/release-process.md 及
/// pubspec `+<code>` 后缀同口径（major*100 + minor*10 + patch）。
/// 曾经分叉为 major*10000 + minor*100 + patch，导致 GitHub 通道
/// （fromGitHubRelease→semverToCode vs 当前 AppConfig.appVersionCode）
/// 同版本恒判"有更新"。
void main() {
  test('semverToCode 与发布流程公式一致：2.5.1 → 251', () {
    expect(semverToCode('2.5.1'), 251);
    expect(semverToCode('2.4.2'), 242);
    expect(semverToCode('v2.5.1'), 251);
  });

  test('semverToCode 单调：版本越大 code 越大', () {
    expect(semverToCode('2.4.2'), lessThan(semverToCode('2.5.1')));
    expect(semverToCode('2.5.1'), lessThan(semverToCode('2.5.2')));
    expect(semverToCode('2.5.1'), lessThan(semverToCode('3.0.0')));
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
