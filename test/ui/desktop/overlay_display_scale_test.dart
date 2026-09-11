// 混合缩放多显示器：悬浮窗位置恢复时的缩放比必须取自「窗口落点所在
// 显示器」，而非主显示器（此前恒用主屏缩放，副屏上位置/尺寸整体偏移）。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiyin_music/services/windows_desktop_lyrics_bridge.dart';

void main() {
  group('WindowsDesktopLyricsBridge.scaleForLogicalOrigin', () {
    // 主屏 1920x1080 @100%，副屏在其右侧 2560x1440 @150%。
    const primary = (area: Rect.fromLTWH(0, 0, 1920, 1080), scale: 1.0);
    const secondary = (
      area: Rect.fromLTWH(1920, 0, 2560, 1440),
      scale: 1.5,
    );
    const displays = [primary, secondary];

    test('原点落在主屏 → 主屏缩放', () {
      expect(
        WindowsDesktopLyricsBridge.scaleForLogicalOrigin(
          displays,
          const Offset(800, 900),
        ),
        1.0,
      );
    });

    test('原点落在副屏 → 副屏缩放（不再误用主屏）', () {
      expect(
        WindowsDesktopLyricsBridge.scaleForLogicalOrigin(
          displays,
          const Offset(3000, 200),
        ),
        1.5,
      );
    });

    test('原点在显示器外的缝隙/负坐标 → null（调用方回退主屏缩放）', () {
      expect(
        WindowsDesktopLyricsBridge.scaleForLogicalOrigin(
          displays,
          const Offset(-2000, 100),
        ),
        isNull,
      );
    });

    test('无显示器信息 → null', () {
      expect(
        WindowsDesktopLyricsBridge.scaleForLogicalOrigin(
          const [],
          const Offset(10, 10),
        ),
        isNull,
      );
    });
  });
}
