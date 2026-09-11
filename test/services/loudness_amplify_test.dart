// 响度均衡放大路径的平台矩阵：Windows 迁移 media_kit(mpv) 后获得与
// Linux 一致的数字放大能力（引擎音量 >1.0，钳制 +6dB ≈ 2.0）。
// 迁移前 Windows 落 AMPLIFY_SKIP（保持用户音量 1.0），本文件锁定迁移后
// 行为，同时锁定 macOS 等无放大能力平台仍走 SKIP。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiyin_music/services/loudness_service.dart';

class _RecordingAudioPlayer extends Fake implements AudioPlayer {
  final volumes = <double>[];
  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumes.add(volume);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAudioPlayer player;
  late LoudnessService service;

  setUp(() async {
    player = _RecordingAudioPlayer();
    SharedPreferences.setMockInitialValues({});
    service = LoudnessService();
    await service.init();
    await service.setEnabled(enabled: true, audioPlayer: player);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> apply(double gainDb) => service.applyGain(
        audioPlayer: player,
        audioSessionId: null,
        gainDb: gainDb,
        userVolume: 1.0,
        instant: true,
      );

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('$platform 轻歌走 mpv 数字放大（+4dB → ×1.585）', () async {
      debugDefaultTargetPlatformOverride = platform;
      await apply(4.0);
      expect(player.volumes.single, closeTo(1.5849, 0.001));
    });

    test('$platform 增益钳制 +6dB（+20dB 输入 → ×1.995）', () async {
      debugDefaultTargetPlatformOverride = platform;
      await apply(20.0);
      expect(player.volumes.single, closeTo(1.9953, 0.001));
    });
  }

  test('windows 响歌衰减路径无回归（-3dB → ×0.708）', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await apply(-3.0);
    expect(player.volumes.single, closeTo(0.7079, 0.001));
  });

  test('macOS 无放大能力仍走 SKIP（保持用户音量）', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await apply(4.0);
    expect(player.volumes.single, 1.0);
  });
}
