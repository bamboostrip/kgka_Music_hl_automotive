import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 响度均衡服务:基于 EBU R128 K-weighted LUFS 分析并应用增益,
/// 消除歌曲间音量差异(避免忽大忽小)。
///
/// 应用策略(详见 [applyGain]):
/// - gain > 0(轻歌放大):Android 用原生 [LoudnessEnhancer],iOS/桌面无放大能力。
/// - gain <= 0(响歌衰减):两端统一用 [AudioPlayer.setVolume]。
///
/// 分析结果按 `song.hash` 缓存到 SharedPreferences(LRU 有上限),避免重复分析。
class LoudnessService {
  LoudnessService();

  static const _channel = MethodChannel('kgka_music_hl/audio_effects');
  static const _cacheKey = 'loudness_cache';
  static const _enabledKey = 'loudness_enabled';

  /// 目标响度(LUFS)。Spotify/Apple 流媒体标准约 -14 LUFS。
  static const double targetLufs = -14.0;

  /// 缓存条目上限,超过则淘汰最久未写入的(简单 LRU,Map 按插入序遍历)。
  static const int _maxCacheSize = 1000;

  /// 增益钳制上限(±dB)。超过则裁剪,避免动态大的歌被推到过载发紧。
  /// Spotify/Apple 的标准化都有限幅,不会无脑放大。
  static const double _maxGainDb = 6.0;

  /// 增益渐变时长(ms)。分析完成瞬间切换增益会有"音量突然塌下去"的突兀感,
  /// 用此时长平滑过渡到目标音量,人耳对 250ms 内的渐变几乎无感。
  static const int _rampDurationMs = 250;

  final Map<String, double> _cache = {}; // hash → measured lufs
  bool _enabled = false;
  bool _initialized = false;
  // setVolume 渐变定时器,新 ramp 开始前取消旧的,保证只有一条 ramp 在跑。
  Timer? _volumeRampTimer;

  bool get isEnabled => _enabled;
  bool get isInitialized => _initialized;

  /// 清空全部响度分析缓存(供设置页"缓存管理"调用)。下次播放会重新分析。
  Future<void> clearCache() async {
    _cache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  /// 缓存条目数(供 UI 展示)。
  int get cacheCount => _cache.length;

  /// 快速查缓存计算增益(已钳制),不触发原生分析。
  /// 命中返回 (gainDb, true);未命中返回 (null, false)。
  /// 供 controller 在"首播前"判断:命中则首播即应用正确增益(instant),
  /// 未命中才在播放中分析后渐变应用。
  ({double? gainDb, bool fromCache}) gainFromCache(String songHash) {
    if (!_enabled || songHash.isEmpty) return (gainDb: null, fromCache: false);
    final cached = _cache[songHash];
    if (cached == null) return (gainDb: null, fromCache: false);
    return (gainDb: _clampedGainFromLufs(cached), fromCache: true);
  }

  /// 是否支持原生 LUFS 分析(Android/iOS)。
  /// 桌面/Web 不支持。
  bool get isAnalysisSupported => !kIsWeb;

  /// 初始化:加载缓存与开关状态。
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    final json = prefs.getString(_cacheKey);
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _cache.addAll(map.map((k, v) => MapEntry(k, (v as num).toDouble())));
      } catch (_) {
        // 缓存损坏,忽略
      }
    }
    _initialized = true;
  }

  /// 开关响度均衡。关闭时立即重置增益。
  Future<void> setEnabled({
    required bool enabled,
    required AudioPlayer audioPlayer,
    int? audioSessionId,
  }) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!enabled) {
      await resetGain(
        audioPlayer: audioPlayer,
        audioSessionId: audioSessionId,
      );
    }
  }

  /// 由实测 LUFS 计算应用增益,并钳制到 [_maxGainDb]。
  /// 缓存里始终存原始 LUFS,钳制只发生在计算 gain 这一步,
  /// 保证存储值、UI 显示、实际应用三者一致。
  double _clampedGainFromLufs(double lufs) =>
      (targetLufs - lufs).clamp(-_maxGainDb, _maxGainDb);

  /// 分析歌曲响度并计算应应用的增益(dB,已钳制)。
  /// 正数=需放大,负数=需衰减,null=无法分析/未启用。
  Future<double?> analyzeAndComputeGain({
    required String songHash,
    required String url,
  }) async {
    if (!_enabled || songHash.isEmpty) return null;

    // 1. 查缓存(命中则重新排队,保证常用歌曲不被淘汰)
    final cached = _cache.remove(songHash);
    if (cached != null) {
      _cache[songHash] = cached;
      return _clampedGainFromLufs(cached);
    }

    // 2. 调原生分析
    if (!isAnalysisSupported) return null;
    try {
      final result = await _channel.invokeMethod<Map>('analyzeLoudness', {
        'url': url,
      });
      if (result == null) return null;
      final lufs = (result['lufs'] as num?)?.toDouble();
      if (lufs == null || !lufs.isFinite) return null;
      final gain = _clampedGainFromLufs(lufs);

      // 3. 缓存原始 LUFS(LRU:命中后重新排队,写入时超限淘汰最早条目)
      _cache.remove(songHash); // 先移除以保证它排到末尾
      _cache[songHash] = lufs;
      while (_cache.length > _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }
      unawaited(_persistCache());
      return gain;
    } on PlatformException catch (e) {
      debugPrint('[loudness] analyze failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 应用增益。
  ///
  /// 按增益正负分流,保证两端语义一致:
  /// - gain > 0(歌曲偏轻,需放大):Android 用 [LoudnessEnhancer] 放大
  ///   (官方仅支持正向放大),setVolume 保持 1.0;iOS/桌面无原生放大,
  ///   只能保持 1.0。
  /// - gain <= 0(歌曲偏响,需衰减):两端统一用 [AudioPlayer.setVolume]
  ///   衰减。Android 的 LoudnessEnhancer 不支持负增益(衰减属未定义行为,
  ///   多数设备无效),故响歌也走 setVolume。
  /// - gain 为 null/非有限/未启用:重置为原始音量。
  ///
  /// 增益先钳制到 [_maxGainDb] 避免过载;setVolume 的变化走渐变(ramp),
  /// 消除"分析完成后音量瞬间塌下去"的突兀感。Android LoudnessEnhancer
  /// 本身是 DRC 类效果,内置平滑,无需渐变。
  Future<void> applyGain({
    required AudioPlayer audioPlayer,
    required int? audioSessionId,
    required double? gainDb,
    /// true=缓存命中/首播前已知增益,直接应用无需渐变;false=播放中分析完成,
    /// 需渐变避免跳变。默认 false(保守,有渐变更安全)。
    bool instant = false,
  }) async {
    if (!_enabled || gainDb == null || !gainDb.isFinite) {
      await resetGain(
        audioPlayer: audioPlayer,
        audioSessionId: audioSessionId,
      );
      return;
    }

    // 防御性二次钳制:正常流程增益已在 analyzeAndComputeGain/gainFromCache 钳过,
    // 这里再 clamp 一次保证任何来源的值都不会越界。
    final clampedGain = gainDb.clamp(-_maxGainDb, _maxGainDb);

    if (clampedGain <= 0) {
      // 响歌衰减:LoudnessEnhancer 不支持负增益,统一走 setVolume
      final volume = pow(10, clampedGain / 20).toDouble().clamp(0.0, 1.0);
      await _disableNativeEnhancer(audioSessionId);
      await _setVolumeRamped(audioPlayer, volume, instant);
      return;
    }

    // 轻歌放大:Android 优先用 LoudnessEnhancer,失败/其他平台降级 setVolume(=1.0)
    if (defaultTargetPlatform == TargetPlatform.android) {
      final gainMb = (clampedGain * 100).round().clamp(0, 1500);
      try {
        await _channel.invokeMethod<bool>('configureLoudnessGain', {
          'audioSessionId': audioSessionId,
          'enabled': true,
          'gainMb': gainMb,
        });
        // 放大用 LoudnessEnhancer,setVolume 保持 1.0 避免双重增益
        await audioPlayer.setVolume(1.0);
        return;
      } on PlatformException catch (e) {
        debugPrint('[loudness] applyGain(android) failed: $e');
      } on MissingPluginException {
        // 降级到 setVolume
      }
    }
    // iOS/桌面:无法放大,setVolume 保持 1.0
    await audioPlayer.setVolume(1.0);
  }

  /// 平滑过渡 setVolume。instant=true 直接设置(缓存命中首播);否则在
  /// [_rampDurationMs] 内线性插值,消除音量突变。
  Future<void> _setVolumeRamped(
    AudioPlayer audioPlayer,
    double targetVolume, [
    bool instant = false,
  ]) async {
    _volumeRampTimer?.cancel();
    final current = audioPlayer.volume;
    if (instant || (current - targetVolume).abs() < 0.002) {
      await audioPlayer.setVolume(targetVolume);
      return;
    }
    // 20ms 步进,总时长 _rampDurationMs
    const steps = 12;
    final stepDuration = _rampDurationMs ~/ steps;
    var i = 0;
    final completer = Completer<void>();
    _volumeRampTimer = Timer.periodic(
      Duration(milliseconds: stepDuration),
      (t) {
        i++;
        final t01 = i / steps;
        final v = current + (targetVolume - current) * t01;
        audioPlayer.setVolume(v.clamp(0.0, 1.0));
        if (i >= steps) {
          t.cancel();
          audioPlayer.setVolume(targetVolume);
          completer.complete();
        }
      },
    );
    return completer.future;
  }

  /// 禁用原生 LoudnessEnhancer(切到 setVolume 衰减模式时调用)。
  Future<void> _disableNativeEnhancer(int? audioSessionId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('configureLoudnessGain', {
        'audioSessionId': audioSessionId,
        'enabled': false,
        'gainMb': 0,
      });
    } on PlatformException catch (_) { // ignore: empty_catches
      // 禁用失败不影响 setVolume 衰减
    } on MissingPluginException { // ignore: empty_catches
      // 插件未注册(非 Android),忽略
    }
  }

  /// 重置增益(关闭/异常时恢复原始音量)。渐变回到 1.0 避免关开关时跳变。
  Future<void> resetGain({
    required AudioPlayer audioPlayer,
    int? audioSessionId,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<bool>('configureLoudnessGain', {
          'audioSessionId': audioSessionId,
          'enabled': false,
          'gainMb': 0,
        });
      } on PlatformException catch (_) { // ignore: empty_catches
        // 重置/释放失败不影响主流程
      } on MissingPluginException { // ignore: empty_catches
        // 插件未注册(非 Android),忽略
      }
    }
    await _setVolumeRamped(audioPlayer, 1.0, false);
  }

  /// 释放原生 LoudnessEnhancer(App 退出/释放时)。
  Future<void> releaseNative() async {
    _volumeRampTimer?.cancel();
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod<bool>('releaseLoudnessGain');
      } on PlatformException catch (_) { // ignore: empty_catches
        // 重置/释放失败不影响主流程
      } on MissingPluginException { // ignore: empty_catches
        // 插件未注册(非 Android),忽略
      }
    }
  }

  Future<void> _persistCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(_cache));
  }
}
