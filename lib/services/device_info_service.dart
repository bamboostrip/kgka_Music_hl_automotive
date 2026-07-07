import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备类型检测服务。
///
/// 通过 MethodChannel 调用原生层判断是否为 Android Automotive 车机。
/// 非 Android 平台恒返回 false。
class DeviceInfoService {
  const DeviceInfoService();

  static const MethodChannel _channel = MethodChannel('kgka_music_hl/device');

  static bool get isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  /// 是否为 Android Automotive 车机。
  ///
  /// 仅判断 FEATURE_AUTOMOTIVE，不会误判插电平板。
  Future<bool> isAutomotive() async {
    if (!isSupportedPlatform) return false;
    try {
      return await _channel.invokeMethod<bool>('isAutomotive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
