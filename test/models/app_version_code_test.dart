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

  test('同版本 GitHub 信息不判为更新（口径分叉回归）', () {
    final fromGithub = AppVersionInfo.fromGitHubRelease(
      const {'tag_name': 'v2.5.1', 'body': '', 'assets': []},
    );
    final current = normalizedVersionCode(AppConfig.appVersionCode);
    expect(fromGithub.versionCode, current);
    expect(fromGithub.isNewerThanCurrent, isFalse);
  });

  test('高版本 GitHub 仍判为更新', () {
    final newer = AppVersionInfo.fromGitHubRelease(
      const {'tag_name': 'v2.5.2', 'body': '', 'assets': []},
    );
    expect(newer.isNewerThanCurrent, isTrue);
  });
}
