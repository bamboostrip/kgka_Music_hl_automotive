import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_version.dart';
import 'music_api.dart';

class AppUpdateService {
  AppUpdateService(this._api);

  final MusicApi _api;

  static bool get isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<AppVersionInfo?> checkForUpdate() async {
    if (!isSupportedPlatform) {
      return null;
    }

    final latest = await _api.latestAppVersion(AppUpdatePlatform.android);
    if (!latest.isNewerThanCurrent) {
      return null;
    }
    return latest;
  }

  Future<void> downloadAndInstall(AppVersionInfo version) async {
    if (!version.hasDownloadUrl) {
      throw StateError('更新包下载地址为空');
    }

    final uri = Uri.tryParse(version.downloadUrl);
    if (uri == null) {
      throw StateError('更新包下载地址无效');
    }

    final success = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!success) {
      throw StateError('无法在浏览器中打开下载链接');
    }
  }
}
