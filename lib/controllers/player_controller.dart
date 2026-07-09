import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_models.dart';
import '../services/audio_effects_service.dart';
import '../services/cache_service.dart';
import '../services/desktop_lyrics_service.dart';
import '../services/loudness_service.dart';
import '../services/music_api.dart';
import '../services/music_audio_handler.dart';
import '../services/playback_history_service.dart';
import '../services/playback_stats_service.dart';
import 'download_controller.dart';

enum PlaybackMode { playlistLoop, shuffle, singleLoop }

class AudioEffectPreset {
  const AudioEffectPreset({required this.name, required this.levels});

  final String name;
  final List<int> levels;
}

class PlayerController extends ChangeNotifier {
  static const _listenTimeSettingKey = 'settings.add_listening_time_enabled';
  static const _audioQualitySettingKey = 'settings.audio_quality';
  static const _equalizerEnabledSettingKey = 'settings.equalizer_enabled';
  static const _equalizerLevelsSettingKey = 'settings.equalizer_levels';
  static const _equalizerPresetSettingKey = 'settings.equalizer_preset';
  static const _bassBoostEnabledSettingKey = 'settings.bass_boost_enabled';
  static const _bassBoostStrengthSettingKey = 'settings.bass_boost_strength';
  static const _audioInterruptionEnabledSettingKey =
      'settings.audio_interruption_enabled';
  static const _autoResumeAfterInterruptionSettingKey =
      'settings.auto_resume_after_interruption';
  static const _playbackSpeedSettingKey = 'settings.playback_speed';
  static const _desktopLyricsEnabledSettingKey = 'settings.desktop_lyrics_enabled';
  static const _desktopLyricsSettingsKey = 'settings.desktop_lyrics_settings';
  static const _smartQualitySettingKey = 'settings.smart_quality_enabled';
  static const _listenTimeReportInterval = Duration(minutes: 30);
  static const _listenTimeCheckInterval = Duration(minutes: 1);
  static const _defaultEqualizerLevels = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  static const equalizerPresets = [
    AudioEffectPreset(name: '平直', levels: _defaultEqualizerLevels),
    AudioEffectPreset(
      name: '流行',
      levels: [0, 250, 450, 350, 100, -100, 50, 300, 450, 500],
    ),
    AudioEffectPreset(
      name: '摇滚',
      levels: [500, 350, 150, -100, -250, -150, 150, 350, 550, 650],
    ),
    AudioEffectPreset(
      name: '人声',
      levels: [-250, -150, 0, 250, 500, 550, 350, 100, -100, -200],
    ),
    AudioEffectPreset(
      name: '低音',
      levels: [750, 650, 500, 250, 0, -100, -150, -200, -250, -300],
    ),
    AudioEffectPreset(
      name: '古典',
      levels: [350, 250, 100, 0, 150, 250, 300, 350, 250, 100],
    ),
    AudioEffectPreset(
      name: '电子',
      levels: [650, 450, 120, -120, -180, 100, 350, 550, 650, 700],
    ),
  ];

  /// 下载控制器（由 main.dart 在创建后注入，供 UI 访问下载功能）。
  DownloadController? downloadController;

  /// 缓存服务（由 main.dart 在创建后注入，用于歌词等缓存）。
  CacheService? cacheService;

  PlayerController(this._api, this._audioHandler) {
    unawaited(_restoreSettings());
    _audioHandler.attachTransportControls(onNext: next, onPrevious: previous);
    _desktopLyrics.setVisibilityChangedHandler(_handleDesktopLyricsVisibility);
    _positionSub = audioPlayer.positionStream.listen((value) {
      if (!_isSeeking) {
        _setPositionBase(value, playing: isPlaying);
      }
      _maybeCompleteFromPosition(value);
      _maybeSyncDesktopLyricFromPosition();
      notifyListeners();
    });
    // Send timing anchors; Android animates karaoke progress at display refresh.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (_shouldShowDesktopLyrics &&
          isPlaying &&
          lyrics.isNotEmpty &&
          !_isScrubbing) {
        _syncDesktopKaraokeProgress();
      }
    });
    _durationSub = audioPlayer.durationStream.listen((value) {
      duration = value ?? Duration.zero;
      notifyListeners();
    });
    _stateSub = audioPlayer.playerStateStream.listen((value) {
      isPlaying = value.playing;
      isBuffering =
          value.processingState == ProcessingState.loading ||
          value.processingState == ProcessingState.buffering;
      if (!_isSeeking) {
        _setPositionBase(audioPlayer.position, playing: isPlaying);
      }
      _syncListeningTimeTracker();
      _syncDesktopPlayState();
      notifyListeners();
    });
    _processingStateSub = audioPlayer.processingStateStream.distinct().listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        unawaited(_handleCompleted());
      }
    });
    _androidAudioSessionSub = audioPlayer.androidAudioSessionIdStream.listen((
      sessionId,
    ) {
      _androidAudioSessionId = sessionId;
      unawaited(_refreshEqualizerConfig());
      unawaited(_applyEqualizer());
      unawaited(_applyBassBoost());
      unawaited(_applyLoudnessGain());
    });
    unawaited(_setupAudioSessionListeners());
    unawaited(_loudness.init());
  }

  final MusicApi _api;
  final MusicAudioHandler _audioHandler;
  final AudioEffectsService _audioEffects = AudioEffectsService();
  final DesktopLyricsService _desktopLyrics = DesktopLyricsService();
  final PlaybackHistoryService _historyService = PlaybackHistoryService();
  final PlaybackStatsService _statsService = PlaybackStatsService();
  final LoudnessService _loudness = LoudnessService();
  double? _pendingGainDb; // 当前歌曲分析得到的待应用增益(dB)
  // 切歌竞态守卫:每次发起分析递增,回调比对序号,不一致则丢弃旧结果。
  int _loudnessSerial = 0;
  // 当前歌曲实际播放 URL,供"开关开启时分析当前歌曲"复用,避免重新解析。
  String? _currentLoudnessUrl;

  AudioPlayer get audioPlayer => _audioHandler.audioPlayer;

  MusicApi get api => _api;

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<ProcessingState> _processingStateSub;
  late final StreamSubscription<int?> _androidAudioSessionSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  final Stopwatch _positionClock = Stopwatch();
  final _random = math.Random();
  Timer? _completionFallbackTimer;
  Timer? _listenTimeTimer;
  DateTime? _listenTimeStartedAt;
  Duration _pendingListenTime = Duration.zero;
  bool _isReportingListenTime = false;
  int _seekSerial = 0;
  bool _isSeeking = false;
  bool _isScrubbing = false;
  bool _isHandlingCompletion = false;
  String? _completedSongHash;
  bool _isAppForeground = true;
  bool _desktopLyricsPreviewVisible = false;

  Song? currentSong;
  List<Song> queue = const [];
  List<LyricLine> lyrics = const [];
  PlaybackMode playbackMode = PlaybackMode.playlistLoop;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  bool isBuffering = false;
  bool isPreparing = false;
  bool addListeningTimeEnabled = true;
  AudioQuality audioQuality = AudioQuality.standard;
  /// 是否开启音质智能切换（播放失败时自动降级重试）。
  bool smartQualityEnabled = false;
  double playbackSpeed = 1.0;
  bool equalizerEnabled = false;
  List<int> equalizerLevels = List<int>.of(_defaultEqualizerLevels);
  String equalizerPresetName = '平直';
  EqualizerConfig equalizerConfig = EqualizerConfig.fallback(
    _defaultEqualizerLevels,
  );
  bool bassBoostEnabled = false;
  double bassBoostStrength = 0.45;
  bool audioInterruptionEnabled = true;
  bool autoResumeAfterInterruption = false;
  bool desktopLyricsEnabled = false;
  DesktopLyricsSettings desktopLyricsSettings = const DesktopLyricsSettings();
  Timer? _autoResumeTimer;
  Duration? sleepTimerRemaining;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEnd;
  bool _sleepFinishCurrentSong = false;
  bool _sleepFinishCurrentSongOption = false;
  String? errorMessage;
  int seekRevision = 0;
  int? _androidAudioSessionId;
  bool get isScrubbing => _isScrubbing;
  bool get isAudioEffectsSupported => _audioEffects.isAudioEffectsSupported;
  bool get isBassBoostSupported => _audioEffects.isBassBoostSupported;
  bool get loudnessEnabled => _loudness.isEnabled;
  bool get isLoudnessAnalysisSupported => _loudness.isAnalysisSupported;
  String get audioEffectsLabel {
    if (!isAudioEffectsSupported) {
      return '当前平台暂不支持';
    }
    if (equalizerEnabled) {
      return '均衡器：$equalizerPresetName';
    }
    if (bassBoostEnabled) {
      return 'Bass ${(bassBoostStrength * 100).round()}%';
    }
    return '关闭';
  }

  String get playbackSpeedLabel {
    if (playbackSpeed == playbackSpeed.roundToDouble()) {
      return '${playbackSpeed.round()}x';
    }
    return '${playbackSpeed}x';
  }

  Duration get smoothPosition {
    if (_isScrubbing) {
      return position;
    }
    if (!isPlaying) {
      return position;
    }
    final value = position + _positionClock.elapsed;
    if (duration > Duration.zero && value > duration) {
      return duration;
    }
    return value;
  }

  int get currentIndex {
    final song = currentSong;
    if (song == null) {
      return -1;
    }
    return queue.indexWhere((item) => item.hash == song.hash);
  }

  int get activeLyricIndex {
    if (lyrics.isEmpty) {
      return -1;
    }
    var index = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (smoothPosition >= lyrics[i].time) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  String get playbackModeLabel {
    return switch (playbackMode) {
      PlaybackMode.playlistLoop => '歌单循环',
      PlaybackMode.shuffle => '随机播放',
      PlaybackMode.singleLoop => '单曲循环',
    };
  }

  PlaybackMode cyclePlaybackMode() {
    playbackMode = switch (playbackMode) {
      PlaybackMode.playlistLoop => PlaybackMode.shuffle,
      PlaybackMode.shuffle => PlaybackMode.singleLoop,
      PlaybackMode.singleLoop => PlaybackMode.playlistLoop,
    };
    notifyListeners();
    return playbackMode;
  }

  Future<void> setAddListeningTimeEnabled(bool enabled) async {
    if (addListeningTimeEnabled == enabled) {
      return;
    }
    addListeningTimeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_listenTimeSettingKey, enabled);
    if (!enabled) {
      _resetListeningTimeTracker();
    } else {
      _syncListeningTimeTracker();
    }
    notifyListeners();
  }

  Future<void> playSong(Song song, {List<Song>? queue}) async {
    _completionFallbackTimer?.cancel();
    _completedSongHash = null;
    isPreparing = true;
    errorMessage = null;
    currentSong = song;
    if (queue != null && queue.isNotEmpty) {
      this.queue = queue;
    } else if (this.queue.isEmpty) {
      this.queue = [song];
    }
    lyrics = const [];
    _lastDesktopLyricIndex = -1;
    notifyListeners();
    unawaited(_syncDesktopLyricsVisibility());

    try {
      String url;
      String? networkUrl;
      final local = downloadController?.localPathFor(song, audioQuality);
      if (local != null) {
        url = local;
      } else if (song.source == SongSource.local) {
        url = song.id;
      } else {
        final playUrl = await _resolvePlayUrl(song);
        if (playUrl.url.isEmpty) {
          throw Exception(
            song.isCloudDrive
                ? '云盘歌曲暂时没有可播放地址'
                : song.source == SongSource.netease
                    ? '网易云歌曲暂时没有可播放地址'
                    : '这首歌暂时没有可播放地址',
          );
        }
        url = playUrl.url;
        networkUrl = playUrl.url;
      }
      // 响度均衡:先查缓存,命中则首播前即应用正确增益(instant,无跳变);
      // 未命中则播放中分析,完成后渐变(ramp)应用。
      _currentLoudnessUrl = url;
      final pre = _loudness.gainFromCache(song.hash);
      if (pre.fromCache) {
        _pendingGainDb = pre.gainDb;
        unawaited(_applyLoudnessGain(instant: true));
      }
      unawaited(_analyzeAndApplyLoudness(song: song, url: url));
      await _audioHandler.loadSong(
        song: song,
        url: url,
        queueSongs: this.queue,
        queueIndex: currentIndex,
      );
      isPreparing = false;
      notifyListeners();
      unawaited(loadLyrics(song));
      await _audioHandler.play();
      // 记录播放历史与本地播放统计（后台执行，不阻塞播放）
      unawaited(_historyService.record(song));
      unawaited(_statsService.recordPlay(song));
      // 首播后后台缓存（仅当本次用的是网络 URL）
      if (networkUrl != null) {
        unawaited(
          downloadController?.cacheForPlayback(song, audioQuality, networkUrl),
        );
      }
    } catch (error) {
      errorMessage = error.toString();
      isPreparing = false;
      notifyListeners();
    } finally {
      if (isPreparing) {
        isPreparing = false;
        notifyListeners();
      }
    }
  }

  /// 解析播放地址。
  ///
  /// - 云盘歌曲走 [MusicApi.cloudSongUrl]
  /// - 网易云歌曲使用外链地址
  /// - 其它歌曲走 [MusicApi.songUrl]，开启智能音质时在网络请求失败
  ///   或返回空地址时自动降级重试（lossless -> high -> standard）。
  Future<PlayUrl> _resolvePlayUrl(Song song) async {
    if (song.source == SongSource.local) {
      return PlayUrl(url: song.id, hash: song.hash);
    }
    if (song.isCloudDrive) {
      return _api.cloudSongUrl(song);
    }
    if (song.source == SongSource.netease) {
      // 网易云歌曲使用外链播放地址
      return PlayUrl(
        url: 'https://music.163.com/song/media/outer/url?id=${song.id}.mp3',
        hash: song.hash,
      );
    }

    try {
      final playUrl = await _api.songUrl(song, quality: audioQuality);
      if (playUrl.url.isNotEmpty || !smartQualityEnabled) {
        return playUrl;
      }
      // 返回空地址：按智能音质策略降级重试
      final fallback = _nextLowerQuality(audioQuality);
      if (fallback == null) return playUrl;
      return _api.songUrl(song, quality: fallback);
    } catch (error) {
      if (!smartQualityEnabled) rethrow;
      // 网络请求失败：尝试降级重试
      final fallback = _nextLowerQuality(audioQuality);
      if (fallback == null) rethrow;
      try {
        final retryUrl = await _api.songUrl(song, quality: fallback);
        if (retryUrl.url.isNotEmpty) {
          debugPrint(
            '[KA Music][smart-quality] ${audioQuality.badge} 失败，'
            '已降级为 ${fallback.badge}',
          );
          return retryUrl;
        }
      } catch (_) {
        // 降级也失败，抛出原始错误
      }
      rethrow;
    }
  }

  /// 返回更低一档的音质；已是最低档时返回 null。
  AudioQuality? _nextLowerQuality(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.lossless:
        return AudioQuality.high;
      case AudioQuality.high:
        return AudioQuality.standard;
      case AudioQuality.standard:
        return null;
    }
  }

  Future<bool> addToQueue(Song song) async {
    final songKey = song.hash.isNotEmpty ? song.hash : song.id;
    final currentSongKey = currentSong == null
        ? ''
        : (currentSong!.hash.isNotEmpty ? currentSong!.hash : currentSong!.id);
    if (songKey.isNotEmpty && songKey == currentSongKey) {
      return false;
    }

    final nextQueue = List<Song>.of(queue);
    final existingIndex = nextQueue.indexWhere((item) {
      final itemKey = item.hash.isNotEmpty ? item.hash : item.id;
      return itemKey.isNotEmpty && itemKey == songKey;
    });
    if (existingIndex >= 0) {
      nextQueue.removeAt(existingIndex);
    }

    if (nextQueue.isEmpty) {
      nextQueue.add(song);
    } else {
      final index = currentIndex;
      final insertIndex = index < 0
          ? 0
          : (index + 1).clamp(0, nextQueue.length);
      nextQueue.insert(insertIndex, song);
    }

    queue = nextQueue;
    await _audioHandler.setSongQueue(
      queueSongs: queue,
      queueIndex: currentIndex,
      currentSong: currentSong,
    );
    notifyListeners();
    return true;
  }

  Future<void> setAudioQuality(
    AudioQuality quality, {
    bool reloadCurrent = false,
  }) async {
    final sameQuality = audioQuality == quality;
    if (sameQuality && !reloadCurrent) {
      return;
    }

    audioQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_audioQualitySettingKey, quality.apiValue);
    notifyListeners();

    if (reloadCurrent && currentSong != null && !sameQuality) {
      await _reloadCurrentSongForQuality();
    }
  }

  /// 开关音质智能切换（播放失败时自动降级重试）。
  Future<void> setSmartQualityEnabled(bool enabled) async {
    if (smartQualityEnabled == enabled) return;
    smartQualityEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_smartQualitySettingKey, enabled);
    notifyListeners();
  }

  /// 读取本地播放统计。
  Future<PlaybackStats> getPlaybackStats() => _statsService.getStats();

  /// 清空本地播放统计。
  Future<void> clearPlaybackStats() => _statsService.clear();

  /// 读取播放历史。
  Future<List<Song>> getPlaybackHistory({int limit = 100}) =>
      _historyService.getHistory(limit: limit);

  /// 清空播放历史。
  Future<void> clearPlaybackHistory() => _historyService.clear();

  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 3.0);
    if ((playbackSpeed - clamped).abs() < 0.001) {
      return;
    }
    playbackSpeed = clamped;
    await audioPlayer.setSpeed(clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playbackSpeedSettingKey, clamped);
    notifyListeners();
  }

  Future<void> setBassBoostEnabled(bool enabled) async {
    if (bassBoostEnabled == enabled) {
      return;
    }
    bassBoostEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bassBoostEnabledSettingKey, enabled);
    await _applyBassBoost();
    notifyListeners();
  }

  Future<void> setBassBoostStrength(
    double strength, {
    bool persist = true,
  }) async {
    final nextStrength = strength.clamp(0.0, 1.0);
    if ((bassBoostStrength - nextStrength).abs() < 0.001) {
      return;
    }
    bassBoostStrength = nextStrength;
    if (bassBoostEnabled) {
      unawaited(_applyBassBoost());
    }
    notifyListeners();

    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_bassBoostStrengthSettingKey, nextStrength);
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    if (equalizerEnabled == enabled) {
      return;
    }
    equalizerEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_equalizerEnabledSettingKey, enabled);
    await _applyEqualizer();
    notifyListeners();
  }

  Future<void> setEqualizerBandLevel(
    int index,
    int levelMillibels, {
    bool persist = true,
  }) async {
    if (index < 0 || index >= equalizerLevels.length) {
      return;
    }
    final clamped = levelMillibels.clamp(
      equalizerConfig.minMillibels,
      equalizerConfig.maxMillibels,
    );
    if (equalizerLevels[index] == clamped) {
      return;
    }
    equalizerLevels = List<int>.of(equalizerLevels)..[index] = clamped;
    equalizerPresetName = '自定义';
    if (equalizerEnabled) {
      unawaited(_applyEqualizer());
    }
    notifyListeners();

    if (persist) {
      await _persistEqualizer();
    }
  }

  Future<void> applyEqualizerPreset(AudioEffectPreset preset) async {
    equalizerPresetName = preset.name;
    equalizerLevels = _levelsForBandCount(
      preset.levels,
      equalizerLevels.length,
    );
    await _persistEqualizer();
    if (equalizerEnabled) {
      await _applyEqualizer();
    }
    notifyListeners();
  }

  Future<void> resetEqualizer() async {
    await applyEqualizerPreset(equalizerPresets.first);
  }

  Future<void> loadLyrics(Song song) async {
    final cache = cacheService;
    final cacheKey = 'cache_lyric_${song.hash}';

    if (song.source == SongSource.local) {
      try {
        final songFile = File(song.id);
        final dotIndex = songFile.path.lastIndexOf('.');
        final lrcPath = '${dotIndex != -1 ? songFile.path.substring(0, dotIndex) : songFile.path}.lrc';
        final file = File(lrcPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          String content;
          try {
            content = utf8.decode(bytes);
          } catch (_) {
            content = utf8.decode(bytes, allowMalformed: true);
          }
          final lines = parseLyrics(content);
          if (currentSong?.hash == song.hash) {
            lyrics = lines;
            notifyListeners();
            _syncDesktopLyrics();
          }
          return;
        }
      } catch (e) {
        debugPrint('Failed to load local lyrics: $e');
      }
      if (currentSong?.hash == song.hash) {
        lyrics = const [];
        notifyListeners();
        _syncDesktopLyrics();
      }
      return;
    }

    // 1. 先读缓存，命中则立即显示（无感）
    if (cache != null) {
      try {
        final cached = await cache.read<List<LyricLine>>(
          cacheKey,
          decode: (json) => (json['lines'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(LyricLine.fromCache)
              .toList(),
          ttl: const Duration(days: 30),
        );
        if (cached != null && !listEquals(lyrics, cached.data) && currentSong?.hash == song.hash) {
          lyrics = cached.data;
          notifyListeners();
          _syncDesktopLyrics();
        }
      } catch (_) {}
    }

    // 2. 后台静默刷新
    try {
      final fresh = await _api.lyrics(song);
      if (currentSong?.hash != song.hash) return; // 已切歌，丢弃
      if (!listEquals(lyrics, fresh)) {
        lyrics = fresh;
        notifyListeners();
      }
      // 写缓存（空歌词也缓存，避免重复请求）
      if (cache != null) {
        unawaited(cache.write(cacheKey, {
          'lines': fresh.map((l) => l.toCache()).toList(),
        }));
      }
    } catch (_) {
      if (currentSong?.hash == song.hash && lyrics.isEmpty) {
        lyrics = const [];
        notifyListeners();
      }
    }
    if (currentSong?.hash == song.hash) {
      _syncDesktopLyrics();
    }
  }

  Future<void> togglePlay() async {
    if (audioPlayer.playing) {
      await _audioHandler.pause();
    } else {
      if (audioPlayer.processingState == ProcessingState.completed) {
        await _audioHandler.seek(Duration.zero);
      }
      await _audioHandler.play();
    }
  }

  void previewSeek(Duration position) {
    _isScrubbing = true;
    _isSeeking = true;
    _setPositionBase(position, playing: false);
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    final serial = ++_seekSerial;
    final target = _clampPosition(position);
    seekRevision++;
    _isScrubbing = false;
    _isSeeking = true;
    _setPositionBase(target, playing: isPlaying);
    notifyListeners();

    try {
      await _audioHandler.seek(target);
      if (serial != _seekSerial) {
        return;
      }
      _setPositionBase(target, playing: isPlaying);
      notifyListeners();
    } finally {
      if (serial == _seekSerial) {
        _isSeeking = false;
        _isScrubbing = false;
      }
    }
  }

  Future<void> next() async {
    final nextSong = _nextSong();
    if (nextSong == null) return;
    await playSong(nextSong, queue: queue);
  }

  Future<void> previous() async {
    final index = currentIndex;
    if (index > 0) {
      await playSong(queue[index - 1], queue: queue);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> _handleCompleted() async {
    if (_isHandlingCompletion || currentSong == null) return;
    if (_completedSongHash == currentSong!.hash) return;
    _isHandlingCompletion = true;
    _completionFallbackTimer?.cancel();
    _completedSongHash = currentSong!.hash;

    try {
      if (_sleepFinishCurrentSong) {
        _sleepFinishCurrentSong = false;
        _sleepFinishCurrentSongOption = false;
        sleepTimerRemaining = null;
        notifyListeners();
        unawaited(_audioHandler.pause());
        return;
      }

      if (playbackMode == PlaybackMode.singleLoop) {
        _completedSongHash = null;
        await _audioHandler.seek(Duration.zero);
        await _audioHandler.play();
        return;
      }

      final nextSong = _nextSong();
      if (nextSong == null) {
        await _audioHandler.seek(Duration.zero);
        return;
      }
      await playSong(nextSong, queue: queue);
    } finally {
      _isHandlingCompletion = false;
    }
  }

  void _maybeCompleteFromPosition(Duration value) {
    if (_isSeeking || _isScrubbing || !isPlaying || duration <= Duration.zero) {
      return;
    }
    if (audioPlayer.processingState == ProcessingState.completed) {
      return;
    }

    final remaining = duration - value;
    if (remaining.inMilliseconds <= 750 &&
        (_completionFallbackTimer?.isActive != true)) {
      final delay =
          (remaining > Duration.zero ? remaining : Duration.zero) +
          const Duration(milliseconds: 180);
      _completionFallbackTimer = Timer(delay, () {
        if (!isPlaying || _isSeeking || _isScrubbing) return;
        final currentPosition = audioPlayer.position;
        if (duration > Duration.zero &&
            duration - currentPosition <= const Duration(milliseconds: 220)) {
          unawaited(_handleCompleted());
        }
      });
    }
  }

  Future<void> _reloadCurrentSongForQuality() async {
    final song = currentSong;
    if (song == null) {
      return;
    }

    final resumePlayback = isPlaying;
    final targetPosition = smoothPosition;
    isPreparing = true;
    errorMessage = null;
    notifyListeners();

    try {
      String url;
      String? networkUrl;
      final local = downloadController?.localPathFor(song, audioQuality);
      if (local != null) {
        url = local;
      } else if (song.source == SongSource.local) {
        url = song.id;
      } else {
        final PlayUrl playUrl;
        if (song.isCloudDrive) {
          playUrl = await _api.cloudSongUrl(song);
        } else if (song.source == SongSource.netease) {
          playUrl = PlayUrl(
            url: 'https://music.163.com/song/media/outer/url?id=${song.id}.mp3',
            hash: song.hash,
          );
        } else {
          playUrl = await _api.songUrl(song, quality: audioQuality);
        }
        if (playUrl.url.isEmpty) {
          throw Exception('当前音质暂时没有可播放地址');
        }
        url = playUrl.url;
        networkUrl = playUrl.url;
      }
      // 响度均衡:切换音质/重载后 URL 可能变化。先查缓存命中即 instant 应用,
      // 未命中则播放中分析后渐变(序号守卫会丢弃旧结果)。
      _currentLoudnessUrl = url;
      final pre = _loudness.gainFromCache(song.hash);
      if (pre.fromCache) {
        _pendingGainDb = pre.gainDb;
        unawaited(_applyLoudnessGain(instant: true));
      }
      unawaited(_analyzeAndApplyLoudness(song: song, url: url));
      await _audioHandler.loadSong(
        song: song,
        url: url,
        queueSongs: queue,
        queueIndex: currentIndex,
      );
      if (targetPosition > Duration.zero) {
        await _audioHandler.seek(_clampPosition(targetPosition));
      }
      if (resumePlayback) {
        await _audioHandler.play();
      }
      // 切音质后后台缓存
      if (networkUrl != null) {
        unawaited(
          downloadController?.cacheForPlayback(song, audioQuality, networkUrl),
        );
      }
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isPreparing = false;
      notifyListeners();
    }
  }

  Future<void> _setupAudioSessionListeners() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(_audioSessionConfiguration);
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // 打断开始：系统可能已自动暂停播放器。
          // 若开启了"阻止打断"，立即恢复播放以对抗暂停。
          if (!audioInterruptionEnabled && isPlaying && currentSong != null) {
            _autoResumeTimer?.cancel();
            _autoResumeTimer = Timer(
              const Duration(milliseconds: 300),
              () {
                if (!isPlaying && currentSong != null) {
                  unawaited(_audioHandler.play());
                }
              },
            );
          }
        } else {
          // 打断结束：若开启了"自动恢复"或"阻止打断"，恢复播放。
          if ((autoResumeAfterInterruption ||
                  (!audioInterruptionEnabled)) &&
              currentSong != null) {
            _autoResumeTimer?.cancel();
            _autoResumeTimer = Timer(
              const Duration(milliseconds: 500),
              () {
                if (!isPlaying && currentSong != null) {
                  unawaited(_audioHandler.play());
                }
              },
            );
          }
        }
      });
      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        if (!audioInterruptionEnabled) {
          // 阻止打断模式下忽略耳机拔出
          return;
        }
        if (autoResumeAfterInterruption && currentSong != null) {
          _autoResumeTimer?.cancel();
          _autoResumeTimer = Timer(
            const Duration(milliseconds: 500),
            () {
              if (!isPlaying && currentSong != null) {
                unawaited(_audioHandler.play());
              }
            },
          );
        }
      });
    } catch (_) {
      // AudioSession not available on this platform
    }
  }

  /// 根据打断设置生成 AudioSessionConfiguration。
  ///
  /// 阻止打断时使用 [AndroidAudioFocusGainType.gain] 并禁用 androidWillPauseWhenDucked，
  /// 向系统声明不希望被其他 App 打断。同时配合 interruptionEventStream 中的
  /// 主动恢复播放作为双保险。
  AudioSessionConfiguration get _audioSessionConfiguration {
    if (audioInterruptionEnabled) {
      return const AudioSessionConfiguration.music();
    }
    // 阻止打断模式：声明需要独占音频焦点，不因降音暂停
    return const AudioSessionConfiguration(
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      // 不因其他 App 降音而暂停
      androidWillPauseWhenDucked: false,
    );
  }

  Future<void> setAudioInterruptionEnabled(bool enabled) async {
    if (audioInterruptionEnabled == enabled) return;
    audioInterruptionEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioInterruptionEnabledSettingKey, enabled);
    // 设置变更后立即重新配置 AudioSession，使新策略生效
    unawaited(_reconfigureAudioSession());
    notifyListeners();
  }

  /// 重新配置 AudioSession 以应用最新的打断策略。
  Future<void> _reconfigureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(_audioSessionConfiguration);
    } catch (_) {
      // AudioSession not available on this platform
    }
  }

  Future<void> setAutoResumeAfterInterruption(bool enabled) async {
    if (autoResumeAfterInterruption == enabled) return;
    autoResumeAfterInterruption = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoResumeAfterInterruptionSettingKey, enabled);
    notifyListeners();
  }

  Future<void> setDesktopLyricsEnabled(bool enabled) async {
    if (desktopLyricsEnabled == enabled) return;
    desktopLyricsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_desktopLyricsEnabledSettingKey, enabled);
    notifyListeners();

    if (enabled) {
      final hasPermission = await _desktopLyrics.checkPermission();
      if (!hasPermission) {
        desktopLyricsEnabled = false;
        await prefs.setBool(_desktopLyricsEnabledSettingKey, false);
        notifyListeners();
        await _desktopLyrics.requestPermission();
        return;
      }
      final song = currentSong;
      if (song != null) {
        await _syncDesktopLyricsVisibility();
      }
    } else {
      await _desktopLyrics.hide();
    }
  }

  bool get _shouldShowDesktopLyrics {
    return desktopLyricsEnabled &&
        currentSong != null &&
        (!_isAppForeground || _desktopLyricsPreviewVisible);
  }

  Future<void> _syncDesktopLyricsVisibility() async {
    if (!_shouldShowDesktopLyrics) {
      await _desktopLyrics.hide();
      return;
    }

    final song = currentSong;
    if (song == null) return;
    final shown = await _desktopLyrics.show(title: song.title, artist: song.artist);
    if (shown) {
      _syncDesktopLyrics();
      _syncDesktopPlayState();
      _syncDesktopKaraokeProgress();
    }
  }

  void _syncDesktopLyrics() {
    if (!_shouldShowDesktopLyrics) return;
    final index = activeLyricIndex;
    if (lyrics.isEmpty) {
      _desktopLyrics.updateLyrics(current: '', next: '');
      return;
    }
    final current = lyrics[index.clamp(0, lyrics.length - 1)].text;
    final nextIndex = index + 1;
    final next = nextIndex < lyrics.length ? lyrics[nextIndex].text : '';
    _desktopLyrics.updateLyrics(current: current, next: next);
  }

  void _syncDesktopPlayState() {
    if (!_shouldShowDesktopLyrics) return;
    _desktopLyrics.updatePlayState(isPlaying: isPlaying);
  }

  int _lastDesktopLyricIndex = -1;

  void _maybeSyncDesktopLyricFromPosition() {
    if (!_shouldShowDesktopLyrics || lyrics.isEmpty) return;
    final index = activeLyricIndex;
    if (index != _lastDesktopLyricIndex) {
      _lastDesktopLyricIndex = index;
      _syncDesktopLyrics();
    }
    // Karaoke progress for current line
    _syncDesktopKaraokeProgress();
  }

  void _syncDesktopKaraokeProgress() {
    if (!_shouldShowDesktopLyrics || lyrics.isEmpty) return;
    final index = activeLyricIndex;
    final line = lyrics[index.clamp(0, lyrics.length - 1)];
    final position = smoothPosition;
    final lineDuration = line.duration ?? _estimatedLineDuration(index);

    if (line.words.isEmpty) {
      // No word-level data: estimate progress from line duration
      final lineStart = line.time.inMilliseconds;
      final lineDurationMs = lineDuration?.inMilliseconds ?? 0;
      if (lineDurationMs > 0) {
        final elapsed = position.inMilliseconds - lineStart;
        final progress = (elapsed / lineDurationMs).clamp(0.0, 1.0);
        _desktopLyrics.updateKaraokeProgress(
          progress: progress,
          lineDuration: lineDuration,
          isPlaying: isPlaying,
        );
      } else {
        _desktopLyrics.updateKaraokeProgress(
          progress: 1.0,
          lineDuration: null,
          isPlaying: isPlaying,
        );
      }
    } else {
      // Word-level: find active word and compute progress
      final lineStart = line.time.inMilliseconds;
      final lineDurationMs = lineDuration?.inMilliseconds ?? 0;
      if (lineDurationMs > 0) {
        final elapsed = position.inMilliseconds - lineStart;
        final progress = (elapsed / lineDurationMs).clamp(0.0, 1.0);
        _desktopLyrics.updateKaraokeProgress(
          progress: progress,
          lineDuration: lineDuration,
          isPlaying: isPlaying,
        );
      }
    }
  }

  Duration? _estimatedLineDuration(int index) {
    if (index < 0 || index >= lyrics.length) {
      return null;
    }
    final explicit = lyrics[index].duration;
    if (explicit != null && explicit > Duration.zero) {
      return explicit;
    }
    if (index + 1 < lyrics.length) {
      final nextDuration = lyrics[index + 1].time - lyrics[index].time;
      if (nextDuration > Duration.zero) {
        return nextDuration;
      }
    }
    if (duration > lyrics[index].time) {
      final tailDuration = duration - lyrics[index].time;
      if (tailDuration > Duration.zero) {
        return tailDuration;
      }
    }
    return null;
  }

  Future<void> updateDesktopLyricsSettings(DesktopLyricsSettings settings) async {
    desktopLyricsSettings = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_desktopLyricsSettingsKey, jsonEncode(settings.toMap()));
    notifyListeners();
    await _desktopLyrics.updateSettings(settings);
  }

  bool get isDesktopLyricsSupported => DesktopLyricsService.isSupportedPlatform;

  void setAppForeground(bool isForeground) {
    if (_isAppForeground == isForeground) return;
    _isAppForeground = isForeground;
    if (desktopLyricsEnabled) {
      _desktopLyrics.setAppForeground(isForeground: isForeground);
      unawaited(_syncDesktopLyricsVisibility());
    }
  }

  Future<void> setDesktopLyricsPreviewVisible(bool visible) async {
    if (_desktopLyricsPreviewVisible == visible) return;
    _desktopLyricsPreviewVisible = visible;
    await _syncDesktopLyricsVisibility();
  }

  Future<void> _handleDesktopLyricsVisibility({
    required bool visible,
    required bool userClosed,
  }) async {
    if (!userClosed || !desktopLyricsEnabled) {
      return;
    }
    desktopLyricsEnabled = false;
    _desktopLyricsPreviewVisible = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_desktopLyricsEnabledSettingKey, false);
    notifyListeners();
  }

  Future<bool> checkDesktopLyricsPermission() =>
      _desktopLyrics.checkPermission();

  Future<void> requestDesktopLyricsPermission() =>
      _desktopLyrics.requestPermission();

  bool get isSleepTimerActive =>
      sleepTimerRemaining != null && sleepTimerRemaining! > Duration.zero;

  bool get isSleepFinishCurrentSong => _sleepFinishCurrentSong;
  bool get sleepFinishCurrentSongOption => _sleepFinishCurrentSongOption;

  /// Set a sleep timer that pauses playback immediately or after current song finishes when it expires.
  void setSleepTimer(Duration duration, {bool finishCurrentSong = false}) {
    _sleepFinishCurrentSongOption = finishCurrentSong;
    _sleepFinishCurrentSong = false;
    _sleepTimer?.cancel();
    _sleepTimerEnd = DateTime.now().add(duration);
    sleepTimerRemaining = duration;
    notifyListeners();

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _sleepTimerEnd;
      if (end == null) return;
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        if (_sleepFinishCurrentSongOption) {
          _sleepTimer?.cancel();
          _sleepTimer = null;
          _sleepTimerEnd = null;
          _sleepFinishCurrentSong = true;
          notifyListeners();
        } else {
          _executeSleepTimer();
        }
      } else {
        sleepTimerRemaining = remaining;
        notifyListeners();
      }
    });
  }

  /// Set a sleep timer that finishes the current song, then stops.
  void setSleepTimerFinishSong(Duration duration) {
    setSleepTimer(duration, finishCurrentSong: true);
  }

  /// Update the sleep timer finish song option dynamically.
  void updateSleepTimerOption(bool finishCurrentSong) {
    if (_sleepTimer != null || _sleepFinishCurrentSong) {
      _sleepFinishCurrentSongOption = finishCurrentSong;
      // If the timer has already expired and is waiting for song to finish,
      // and they turn it OFF, we should stop immediately.
      if (!finishCurrentSong && _sleepFinishCurrentSong) {
        _executeSleepTimer();
      } else {
        notifyListeners();
      }
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEnd = null;
    _sleepFinishCurrentSong = false;
    _sleepFinishCurrentSongOption = false;
    sleepTimerRemaining = null;
    notifyListeners();
  }

  void _executeSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEnd = null;
    _sleepFinishCurrentSong = false;
    _sleepFinishCurrentSongOption = false;
    sleepTimerRemaining = null;
    notifyListeners();
    unawaited(_audioHandler.pause());
  }

  Future<void> _restoreSettings() async {
    final prefs = await SharedPreferences.getInstance();
    addListeningTimeEnabled =
        prefs.getBool(_listenTimeSettingKey) ?? addListeningTimeEnabled;
    audioQuality = AudioQuality.fromApiValue(
      prefs.getString(_audioQualitySettingKey),
    );
    smartQualityEnabled =
        prefs.getBool(_smartQualitySettingKey) ?? smartQualityEnabled;
    equalizerEnabled =
        prefs.getBool(_equalizerEnabledSettingKey) ?? equalizerEnabled;
    equalizerPresetName =
        prefs.getString(_equalizerPresetSettingKey) ?? equalizerPresetName;
    equalizerLevels = _restoreEqualizerLevels(
      prefs.getString(_equalizerLevelsSettingKey),
    );
    equalizerConfig = EqualizerConfig.fallback(equalizerLevels);
    bassBoostEnabled =
        prefs.getBool(_bassBoostEnabledSettingKey) ?? bassBoostEnabled;
    bassBoostStrength =
        prefs.getDouble(_bassBoostStrengthSettingKey) ?? bassBoostStrength;
    audioInterruptionEnabled =
        prefs.getBool(_audioInterruptionEnabledSettingKey) ??
            audioInterruptionEnabled;
    autoResumeAfterInterruption =
        prefs.getBool(_autoResumeAfterInterruptionSettingKey) ??
            autoResumeAfterInterruption;
    playbackSpeed =
        prefs.getDouble(_playbackSpeedSettingKey) ?? playbackSpeed;
    desktopLyricsEnabled =
        prefs.getBool(_desktopLyricsEnabledSettingKey) ?? desktopLyricsEnabled;
    final dlSettingsRaw = prefs.getString(_desktopLyricsSettingsKey);
    if (dlSettingsRaw != null && dlSettingsRaw.isNotEmpty) {
      try {
        final map = jsonDecode(dlSettingsRaw);
        if (map is Map<String, dynamic>) {
          desktopLyricsSettings = DesktopLyricsSettings.fromMap(map);
        }
      } catch (_) {}
    }
    unawaited(audioPlayer.setSpeed(playbackSpeed));
    if (desktopLyricsEnabled) {
      unawaited(_desktopLyrics.updateSettings(desktopLyricsSettings));
    }
    _syncListeningTimeTracker();
    unawaited(_refreshEqualizerConfig());
    unawaited(_applyEqualizer());
    unawaited(_applyBassBoost());
    notifyListeners();
  }

  List<int> _restoreEqualizerLevels(String? raw) {
    if (raw == null || raw.isEmpty) {
      return List<int>.of(_defaultEqualizerLevels);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final levels = decoded
            .whereType<num>()
            .map((value) => value.round())
            .toList();
        if (levels.isNotEmpty) {
          return _levelsForBandCount(levels, _defaultEqualizerLevels.length);
        }
      }
    } catch (_) {}
    return List<int>.of(_defaultEqualizerLevels);
  }

  Future<void> _persistEqualizer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_equalizerEnabledSettingKey, equalizerEnabled);
    await prefs.setString(_equalizerPresetSettingKey, equalizerPresetName);
    await prefs.setString(
      _equalizerLevelsSettingKey,
      jsonEncode(equalizerLevels),
    );
  }

  Future<void> _refreshEqualizerConfig() async {
    if (!isAudioEffectsSupported) {
      return;
    }
    final config = await _audioEffects.equalizerConfig(
      audioSessionId:
          _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
    );
    if (config == null || config.bands.isEmpty) {
      return;
    }
    equalizerConfig = config;
    if (equalizerLevels.length != config.bands.length) {
      equalizerLevels = _levelsForBandCount(
        equalizerLevels,
        config.bands.length,
      );
      unawaited(_persistEqualizer());
    }
    notifyListeners();
  }

  Future<void> _applyEqualizer() async {
    if (!isAudioEffectsSupported) {
      return;
    }
    await _audioEffects.configureEqualizer(
      audioSessionId:
          _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
      enabled: equalizerEnabled,
      levels: equalizerLevels,
    );
  }

  Future<void> _applyBassBoost() async {
    if (!isBassBoostSupported) {
      return;
    }

    await _audioEffects.configureBassBoost(
      audioSessionId:
          _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
      enabled: bassBoostEnabled,
      strength: bassBoostStrength,
    );
  }

  /// 切歌时并行分析响度,完成后应用增益(不阻塞 loadSong/播放)。
  /// 用 [_loudnessSerial] 守护:若分析期间又切了歌,本次结果会被丢弃。
  /// 仅在缓存未命中(需原生解码分析)时触发渐变应用;缓存命中已由
  /// 调用方(loadSong 前)instant 应用,这里 [analyzeAndComputeGain] 会
  /// 再次命中并返回相同值,gain 与 [_pendingGainDb] 一致则跳过重复应用。
  Future<void> _analyzeAndApplyLoudness({
    required Song song,
    required String url,
  }) async {
    final serial = ++_loudnessSerial;
    final gain = await _loudness.analyzeAndComputeGain(
      songHash: song.hash,
      url: url,
    );
    // 切歌守卫:序号不匹配说明期间已切到其它歌曲,丢弃本次结果
    if (serial != _loudnessSerial) return;
    final needsRamp = gain != null && gain != _pendingGainDb;
    _pendingGainDb = gain;
    // gain 为 null(分析失败/未启用)→ reset;否则:缓存命中已 instant 应用
    // 过且值不变则跳过,新分析结果才渐变应用。
    await _applyLoudnessGain(instant: !needsRamp && gain != null);
    notifyListeners(); // 刷新 UI 上的 LUFS/增益显示
  }

  /// 应用当前歌曲的响度增益(sessionId 变化或分析完成时调用)。
  /// [instant]=true 直接设置(缓存命中首播);false 走渐变(播放中分析完成)。
  Future<void> _applyLoudnessGain({bool instant = false}) async {
    await _loudness.applyGain(
      audioPlayer: audioPlayer,
      audioSessionId: _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
      gainDb: _pendingGainDb,
      instant: instant,
    );
  }

  /// 开关响度均衡。
  Future<void> setLoudnessEnabled(bool enabled) async {
    await _loudness.setEnabled(
      enabled: enabled,
      audioPlayer: audioPlayer,
      audioSessionId: _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
    );
    if (enabled) {
      // 开启后,对当前歌曲立即分析并应用(用已解析的真实 URL,避免重新请求)
      final song = currentSong;
      final url = _currentLoudnessUrl;
      if (song != null && url != null && url.isNotEmpty) {
        unawaited(_analyzeAndApplyLoudness(song: song, url: url));
      }
    } else {
      _pendingGainDb = null;
      _loudnessSerial++; // 使任何在途分析结果失效
    }
    notifyListeners();
  }

  /// 响度分析缓存条目数(供设置页展示)。
  int get loudnessCacheCount => _loudness.cacheCount;

  /// 清空响度分析缓存(设置页"缓存管理"调用)。
  /// 清完后若响度开启,重置当前歌曲增益回原始音量,下次切歌重新分析。
  Future<void> clearLoudnessCache() async {
    _loudnessSerial++; // 使任何在途分析结果失效
    _pendingGainDb = null;
    await _loudness.clearCache();
    if (_loudness.isEnabled) {
      await _loudness.resetGain(
        audioPlayer: audioPlayer,
        audioSessionId: _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
      );
    }
    notifyListeners();
  }

  void _syncListeningTimeTracker() {
    final shouldTrack =
        addListeningTimeEnabled && isPlaying && currentSong != null;
    if (shouldTrack) {
      _listenTimeStartedAt ??= DateTime.now();
      _listenTimeTimer ??= Timer.periodic(
        _listenTimeCheckInterval,
        (_) => unawaited(_maybeReportListeningTime()),
      );
      return;
    }

    _pauseListeningTimeTracker();
  }

  void _pauseListeningTimeTracker() {
    final startedAt = _listenTimeStartedAt;
    if (startedAt != null) {
      _pendingListenTime += DateTime.now().difference(startedAt);
      _listenTimeStartedAt = null;
    }
    _listenTimeTimer?.cancel();
    _listenTimeTimer = null;
  }

  void _resetListeningTimeTracker() {
    _listenTimeStartedAt = null;
    _pendingListenTime = Duration.zero;
    _listenTimeTimer?.cancel();
    _listenTimeTimer = null;
  }

  Duration _trackedListeningTime() {
    final startedAt = _listenTimeStartedAt;
    if (startedAt == null) {
      return _pendingListenTime;
    }
    return _pendingListenTime + DateTime.now().difference(startedAt);
  }

  Future<void> _maybeReportListeningTime() async {
    if (_isReportingListenTime || !addListeningTimeEnabled) {
      return;
    }
    if (_trackedListeningTime() < _listenTimeReportInterval) {
      return;
    }

    _isReportingListenTime = true;
    try {
      await _api.addListeningTime();
      // 上报成功，同步记录本地统计的听歌时长
      unawaited(_statsService.addListenTime(_listenTimeReportInterval));
      final stillPlaying = isPlaying && currentSong != null;
      final remainder = _trackedListeningTime() - _listenTimeReportInterval;
      _pendingListenTime = remainder > Duration.zero
          ? remainder
          : Duration.zero;
      _listenTimeStartedAt = stillPlaying ? DateTime.now() : null;
      if (!stillPlaying) {
        _listenTimeTimer?.cancel();
        _listenTimeTimer = null;
      }
    } catch (error) {
      debugPrint('[KA Music][listen-time] report failed: $error');
    } finally {
      _isReportingListenTime = false;
    }
  }

  Song? _nextSong() {
    if (queue.isEmpty) {
      return currentSong;
    }

    final index = currentIndex;
    if (playbackMode == PlaybackMode.shuffle) {
      if (queue.length == 1) return queue.first;

      var nextIndex = _random.nextInt(queue.length);
      if (index >= 0) {
        while (nextIndex == index) {
          nextIndex = _random.nextInt(queue.length);
        }
      }
      return queue[nextIndex];
    }

    if (index >= 0 && index < queue.length - 1) {
      return queue[index + 1];
    }

    return queue.first;
  }

  @override
  void dispose() {
    _pauseListeningTimeTracker();
    _autoResumeTimer?.cancel();
    _sleepTimer?.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _stateSub.cancel();
    _processingStateSub.cancel();
    _androidAudioSessionSub.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    _completionFallbackTimer?.cancel();
    unawaited(
      _audioEffects.configureEqualizer(
        audioSessionId:
            _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
        enabled: false,
        levels: equalizerLevels,
      ),
    );
    unawaited(
      _audioEffects.configureBassBoost(
        audioSessionId:
            _androidAudioSessionId ?? audioPlayer.androidAudioSessionId,
        enabled: false,
        strength: bassBoostStrength,
      ),
    );
    unawaited(_loudness.releaseNative());
    _audioHandler.detachTransportControls();
    _desktopLyrics.setVisibilityChangedHandler(null);
    unawaited(_audioHandler.close());
    unawaited(_desktopLyrics.hide());
    super.dispose();
  }

  void _setPositionBase(Duration value, {required bool playing}) {
    position = _clampPosition(value);
    _positionClock
      ..stop()
      ..reset();
    if (playing) {
      _positionClock.start();
    }
  }

  Duration _clampPosition(Duration value) {
    if (value < Duration.zero) {
      return Duration.zero;
    }
    if (duration > Duration.zero && value > duration) {
      return duration;
    }
    return value;
  }

  List<int> _levelsForBandCount(List<int> source, int count) {
    if (count <= 0) {
      return const [];
    }
    if (source.length == count) {
      return List<int>.of(source);
    }
    if (source.length == 1) {
      return List<int>.filled(count, source.first);
    }

    return [
      for (var index = 0; index < count; index++)
        source[((index / math.max(1, count - 1)) * (source.length - 1))
            .round()],
    ];
  }
}
