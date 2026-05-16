import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/music_models.dart';
import '../services/music_api.dart';

class PlayerController extends ChangeNotifier {
  PlayerController(this._api) {
    _positionSub = audioPlayer.positionStream.listen((value) {
      if (!_isSeeking) {
        _setPositionBase(value, playing: isPlaying);
      }
      notifyListeners();
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
      notifyListeners();
    });
  }

  final MusicApi _api;
  final AudioPlayer audioPlayer = AudioPlayer();

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<PlayerState> _stateSub;
  final Stopwatch _positionClock = Stopwatch();
  int _seekSerial = 0;
  bool _isSeeking = false;
  bool _isScrubbing = false;

  Song? currentSong;
  List<Song> queue = const [];
  List<LyricLine> lyrics = const [];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  bool isBuffering = false;
  bool isPreparing = false;
  String? errorMessage;
  int seekRevision = 0;
  bool get isScrubbing => _isScrubbing;

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

  Future<void> playSong(Song song, {List<Song>? queue}) async {
    isPreparing = true;
    errorMessage = null;
    currentSong = song;
    if (queue != null && queue.isNotEmpty) {
      this.queue = queue;
    } else if (this.queue.isEmpty) {
      this.queue = [song];
    }
    lyrics = const [];
    notifyListeners();

    try {
      final playUrl = await _api.songUrl(song);
      if (playUrl.url.isEmpty) {
        throw Exception('这首歌暂时没有可播放地址');
      }
      await audioPlayer.setUrl(playUrl.url);
      isPreparing = false;
      notifyListeners();
      unawaited(loadLyrics(song));
      unawaited(audioPlayer.play());
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

  Future<void> loadLyrics(Song song) async {
    try {
      lyrics = await _api.lyrics(song);
      notifyListeners();
    } catch (_) {
      lyrics = const [];
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (audioPlayer.playing) {
      await audioPlayer.pause();
    } else {
      await audioPlayer.play();
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
      await audioPlayer.seek(target);
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
    final index = currentIndex;
    if (index >= 0 && index < queue.length - 1) {
      await playSong(queue[index + 1], queue: queue);
    }
  }

  Future<void> previous() async {
    final index = currentIndex;
    if (index > 0) {
      await playSong(queue[index - 1], queue: queue);
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  void dispose() {
    _positionSub.cancel();
    _durationSub.cancel();
    _stateSub.cancel();
    audioPlayer.dispose();
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
}
