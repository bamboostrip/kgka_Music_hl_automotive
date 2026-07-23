# 播放状态持久化 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 退出应用时保存播放队列、当前歌曲、播放模式，启动时恢复；自动播放改为播放上次歌曲。

**架构：** 在 PlayerController 中新增 `_savePlaybackState()` / `_restorePlaybackState()` 方法，使用 SharedPreferences 存储 JSON。保存操作通过 500ms 防抖 Timer 合并。新增 `resumePlayback()` 方法供自动播放调用，内含按播放模式的失败重试逻辑。

**技术栈：** Flutter / Dart / SharedPreferences / just_audio / audio_service

---

## 文件结构

| 文件 | 操作 | 职责 |
|---|---|---|
| `lib/models/music_models.dart` | 修改 | Song.toCache 补充 source 字段，Song.fromCache 对应恢复 |
| `lib/controllers/player_controller.dart` | 修改 | 新增持久化 key、防抖 Timer、保存/恢复方法、resumePlayback、调用点 |
| `lib/ui/pages/home_page.dart` | 修改 | _checkAndAutoPlay 改为优先使用已恢复状态 |
| `lib/ui/pages/settings_page.dart` | 修改 | 自动播放开关副标题文案 |

---

### 任务 1：Song 序列化补充 source 字段

**文件：**
- 修改：`lib/models/music_models.dart:976-1020`（Song.toCache 和 Song.fromCache）

- [ ] **步骤 1：修改 Song.toCache() 添加 source 字段**

在 `lib/models/music_models.dart` 的 `Song.toCache()` 方法中，在 `if (isCloudDrive) 'isCloudDrive': true,` 之后添加 source 字段：

```dart
  Map<String, dynamic> toCache() => {
        'id': id,
        'title': title,
        'artist': artist,
        'hash': hash,
        'albumId': albumId,
        'albumAudioId': albumAudioId,
        'albumName': albumName,
        'coverUrl': coverUrl,
        'durationMs': duration?.inMilliseconds,
        'artists': artists
            .map((a) => {
                  'id': a.id,
                  'name': a.name,
                  'avatarUrl': a.avatarUrl,
                })
            .toList(),
        if (isCloudDrive) 'isCloudDrive': true,
        if (source != SongSource.kugou) 'source': source.name,
      };
```

- [ ] **步骤 2：修改 Song.fromCache() 恢复 source 字段**

在 `Song.fromCache` 工厂构造函数中，在 `isCloudDrive: json['isCloudDrive'] == true,` 之后添加 source 恢复：

```dart
  factory Song.fromCache(Map<String, dynamic> json) {
    return Song(
      id: asString(json['id']) ?? '',
      title: asString(json['title']) ?? '未知歌曲',
      artist: asString(json['artist']) ?? '未知艺人',
      hash: asString(json['hash']) ?? '',
      albumId: asString(json['albumId']),
      albumAudioId: asString(json['albumAudioId']),
      albumName: asString(json['albumName']),
      coverUrl: asString(json['coverUrl']),
      duration: durationFromMilliseconds(json['durationMs']),
      artists: asList(json['artists'])
          .whereType<Map<String, dynamic>>()
          .map((a) => ArtistRef(
                id: asString(a['id']) ?? '',
                name: asString(a['name']) ?? '',
                avatarUrl: asString(a['avatarUrl']),
              ))
          .where((artist) => artist.name.isNotEmpty)
          .toList(),
      isCloudDrive: json['isCloudDrive'] == true,
      source: json['source'] is String
          ? SongSource.values.firstWhere(
              (s) => s.name == json['source'],
              orElse: () => SongSource.kugou,
            )
          : SongSource.kugou,
    );
  }
```

- [ ] **步骤 3：运行静态分析验证**

运行：`flutter analyze lib/models/music_models.dart`
预期：无错误

- [ ] **步骤 4：Commit**

```bash
git add lib/models/music_models.dart
git commit -m "feat(models): add source field to Song cache serialization"
```

---

### 任务 2：PlayerController 添加持久化保存逻辑

**文件：**
- 修改：`lib/controllers/player_controller.dart`

- [ ] **步骤 1：添加持久化 key 和防抖 Timer 字段**

在 `PlayerController` 类的静态常量区域（`_autoPlayOnDeviceConnectedSettingKey` 之后，约第 53 行），添加：

```dart
  static const _playbackStateKey = 'playback_state';
  static const _playbackStateMaxQueueSize = 200;
```

在实例字段区域（`Timer? _sleepTimer;` 附近，约第 248 行），添加：

```dart
  Timer? _saveStateTimer;
```

- [ ] **步骤 2：添加 _scheduleSavePlaybackState 和 _savePlaybackState 方法**

在 `_restoreSettings()` 方法之前（约第 1438 行前），添加：

```dart
  void _scheduleSavePlaybackState() {
    _saveStateTimer?.cancel();
    _saveStateTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_savePlaybackState());
    });
  }

  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final state = {
      'queue': queue
          .take(_playbackStateMaxQueueSize)
          .map((s) => s.toCache())
          .toList(),
      'currentIndex': currentIndex,
      'playbackMode': playbackMode.name,
    };
    await prefs.setString(_playbackStateKey, jsonEncode(state));
  }
```

- [ ] **步骤 3：在 playSong() 中触发保存**

在 `playSong()` 方法的 `finally` 块末尾（`_isChangingSource = false;` 之后），添加保存调用。

找到 `playSong` 方法的 finally 块（约第 425 行）：

```dart
    } finally {
      _isChangingSource = false;
      if (isPreparing) {
        isPreparing = false;
        notifyListeners();
      }
    }
```

改为：

```dart
    } finally {
      _isChangingSource = false;
      if (isPreparing) {
        isPreparing = false;
        notifyListeners();
      }
      _scheduleSavePlaybackState();
    }
```

- [ ] **步骤 4：在 cyclePlaybackMode() 中触发保存**

找到 `cyclePlaybackMode()` 方法（约第 322 行）：

```dart
  PlaybackMode cyclePlaybackMode() {
    playbackMode = switch (playbackMode) {
      PlaybackMode.playlistLoop => PlaybackMode.shuffle,
      PlaybackMode.shuffle => PlaybackMode.singleLoop,
      PlaybackMode.singleLoop => PlaybackMode.playlistLoop,
    };
    notifyListeners();
    return playbackMode;
  }
```

改为：

```dart
  PlaybackMode cyclePlaybackMode() {
    playbackMode = switch (playbackMode) {
      PlaybackMode.playlistLoop => PlaybackMode.shuffle,
      PlaybackMode.shuffle => PlaybackMode.singleLoop,
      PlaybackMode.singleLoop => PlaybackMode.playlistLoop,
    };
    _scheduleSavePlaybackState();
    notifyListeners();
    return playbackMode;
  }
```

- [ ] **步骤 5：在 replaceQueue() 中触发保存**

找到 `replaceQueue()` 方法（约第 512 行）：

```dart
  Future<void> replaceQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    queue = List<Song>.of(songs);
    await _audioHandler.setSongQueue(
      queueSongs: queue,
      queueIndex: currentIndex,
      currentSong: currentSong,
    );
    notifyListeners();
  }
```

改为：

```dart
  Future<void> replaceQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    queue = List<Song>.of(songs);
    await _audioHandler.setSongQueue(
      queueSongs: queue,
      queueIndex: currentIndex,
      currentSong: currentSong,
    );
    _scheduleSavePlaybackState();
    notifyListeners();
  }
```

- [ ] **步骤 6：在 addSongsToQueue() 中触发保存**

找到 `addSongsToQueue()` 方法末尾的 `notifyListeners();`（约第 570 行附近），在其前面添加 `_scheduleSavePlaybackState();`。

该方法末尾结构为：

```dart
    queue = nextQueue;
    await _audioHandler.setSongQueue(
      queueSongs: queue,
      queueIndex: currentIndex,
      currentSong: currentSong,
    );
    notifyListeners();
    return toInsert.length;
```

改为：

```dart
    queue = nextQueue;
    await _audioHandler.setSongQueue(
      queueSongs: queue,
      queueIndex: currentIndex,
      currentSong: currentSong,
    );
    _scheduleSavePlaybackState();
    notifyListeners();
    return toInsert.length;
```

- [ ] **步骤 7：在 dispose() 中取消防抖 Timer**

找到 `dispose()` 方法（约第 1820 行），在 `_completionFallbackTimer?.cancel();` 之后添加：

```dart
    _saveStateTimer?.cancel();
```

- [ ] **步骤 8：运行静态分析验证**

运行：`flutter analyze lib/controllers/player_controller.dart`
预期：无错误

- [ ] **步骤 9：Commit**

```bash
git add lib/controllers/player_controller.dart
git commit -m "feat(player): add playback state persistence with debounce"
```

---

### 任务 3：PlayerController 添加启动恢复逻辑

**文件：**
- 修改：`lib/controllers/player_controller.dart`

- [ ] **步骤 1：添加 hasRestoredPlaybackState 字段**

在实例字段区域（`bool autoPlayOnStartupEnabled = false;` 附近，约第 232 行），添加：

```dart
  bool hasRestoredPlaybackState = false;
```

- [ ] **步骤 2：添加 _restorePlaybackState 方法**

在 `_restoreSettings()` 方法之后（约第 1500 行后），添加：

```dart
  Future<void> _restorePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playbackStateKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final state = jsonDecode(raw) as Map<String, dynamic>;
      final queueList = (state['queue'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromCache)
          .toList();
      if (queueList.isEmpty) return;

      queue = queueList;
      final index = (state['currentIndex'] as int? ?? 0)
          .clamp(0, queueList.length - 1);
      currentSong = queueList[index];

      final modeName = state['playbackMode'] as String?;
      if (modeName != null) {
        playbackMode = PlaybackMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => PlaybackMode.playlistLoop,
        );
      }

      hasRestoredPlaybackState = true;
      notifyListeners();
    } catch (_) {}
  }
```

- [ ] **步骤 3：在构造函数中调用 _restorePlaybackState**

找到构造函数中的 `unawaited(_restoreSettings());`（约第 96 行），在其后添加：

```dart
    unawaited(_restorePlaybackState());
```

即：

```dart
  PlayerController(this._api, this._audioHandler) {
    unawaited(_restoreSettings());
    unawaited(_restorePlaybackState());
    _audioHandler.attachTransportControls(onNext: next, onPrevious: previous);
```

- [ ] **步骤 4：运行静态分析验证**

运行：`flutter analyze lib/controllers/player_controller.dart`
预期：无错误

- [ ] **步骤 5：Commit**

```bash
git add lib/controllers/player_controller.dart
git commit -m "feat(player): restore playback state on startup"
```

---

### 任务 4：PlayerController 添加 resumePlayback 方法

**文件：**
- 修改：`lib/controllers/player_controller.dart`

- [ ] **步骤 1：添加 resumePlayback 方法**

在 `_restorePlaybackState()` 方法之后添加：

```dart
  /// 尝试播放已恢复的当前歌曲。
  ///
  /// 播放失败时按播放模式处理：
  /// - [PlaybackMode.singleLoop]：不切歌，保留错误信息
  /// - [PlaybackMode.playlistLoop] / [PlaybackMode.shuffle]：自动切下一首重试
  ///
  /// 返回 true 表示成功开始播放。
  Future<bool> resumePlayback() async {
    if (currentSong == null || queue.isEmpty) return false;

    final maxAttempts = queue.length;
    var songToPlay = currentSong!;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      errorMessage = null;
      await playSong(songToPlay, queue: queue);
      if (errorMessage == null) return true;

      if (playbackMode == PlaybackMode.singleLoop) {
        return false;
      }

      final nextSong = _nextSong();
      if (nextSong == null) return false;
      songToPlay = nextSong;
    }

    return false;
  }
```

- [ ] **步骤 2：运行静态分析验证**

运行：`flutter analyze lib/controllers/player_controller.dart`
预期：无错误

- [ ] **步骤 3：Commit**

```bash
git add lib/controllers/player_controller.dart
git commit -m "feat(player): add resumePlayback with mode-aware retry"
```

---

### 任务 5：修改 HomePage 自动播放逻辑

**文件：**
- 修改：`lib/ui/pages/home_page.dart:116-140`（_checkAndAutoPlay 方法）

- [ ] **步骤 1：修改 _checkAndAutoPlay 方法**

找到 `_checkAndAutoPlay` 方法（约第 116 行）：

```dart
  void _checkAndAutoPlay(_HomeData data) {
    if (widget.player.autoPlayOnStartupEnabled &&
        !_hasAutoPlayed &&
        widget.player.currentSong == null) {
      _hasAutoPlayed = true;
      final songs = data.daily.songs;
      if (songs.isNotEmpty) {
        // 必须推迟到首帧构建完成后执行：_checkAndAutoPlay 会在 initState
        // 阶段被同步调用，此时直接调用 playSong 会触发 notifyListeners()，
        // 违反 Flutter "build 阶段不能触发 setState/notifyListeners" 规则。
        // 叠加 Windows 平台 just_audio 的 WinRT MediaPlayer COM 线程在应用
        // 启动早期尚未完全就绪，立即 setUrl()/play() 会与 UI 渲染竞争，
        // 导致 "Lost connection to device" 进程崩溃。
        // Windows 上额外延迟 300ms 让 native 层完全稳定后再启动播放。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final delay = Platform.isWindows
              ? const Duration(milliseconds: 300)
              : Duration.zero;
          Future<void>.delayed(delay, () {
            if (!mounted) return;
            widget.player.playSong(songs.first, queue: songs);
          });
        });
      }
    }
  }
```

替换为：

```dart
  void _checkAndAutoPlay(_HomeData data) {
    if (!widget.player.autoPlayOnStartupEnabled || _hasAutoPlayed) return;
    _hasAutoPlayed = true;

    final hasRestored = widget.player.hasRestoredPlaybackState;
    final songs = data.daily.songs;
    if (!hasRestored && songs.isEmpty) return;

    // 必须推迟到首帧构建完成后执行：_checkAndAutoPlay 会在 initState
    // 阶段被同步调用，此时直接调用 playSong 会触发 notifyListeners()，
    // 违反 Flutter "build 阶段不能触发 setState/notifyListeners" 规则。
    // 叠加 Windows 平台 just_audio 的 WinRT MediaPlayer COM 线程在应用
    // 启动早期尚未完全就绪，立即 setUrl()/play() 会与 UI 渲染竞争，
    // 导致 "Lost connection to device" 进程崩溃。
    // Windows 上额外延迟 300ms 让 native 层完全稳定后再启动播放。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final delay = Platform.isWindows
          ? const Duration(milliseconds: 300)
          : Duration.zero;
      Future<void>.delayed(delay, () {
        if (!mounted) return;
        if (hasRestored) {
          widget.player.resumePlayback();
        } else {
          widget.player.playSong(songs.first, queue: songs);
        }
      });
    });
  }
```

- [ ] **步骤 2：运行静态分析验证**

运行：`flutter analyze lib/ui/pages/home_page.dart`
预期：无错误

- [ ] **步骤 3：Commit**

```bash
git add lib/ui/pages/home_page.dart
git commit -m "feat(home): auto-play restored playback state instead of daily recommendations"
```

---

### 任务 6：更新设置页文案

**文件：**
- 修改：`lib/ui/pages/settings_page.dart:139`

- [ ] **步骤 1：修改自动播放开关副标题**

找到（约第 139 行）：

```dart
                      subtitle: '打开应用时自动加载并播放推荐歌单',
```

替换为：

```dart
                      subtitle: '打开应用时自动播放上次的歌曲',
```

- [ ] **步骤 2：运行静态分析验证**

运行：`flutter analyze lib/ui/pages/settings_page.dart`
预期：无错误

- [ ] **步骤 3：Commit**

```bash
git add lib/ui/pages/settings_page.dart
git commit -m "feat(settings): update auto-play subtitle to reflect new behavior"
```

---

### 任务 7：全量验证

- [ ] **步骤 1：运行全量静态分析**

运行：`flutter analyze`
预期：无错误（warnings 可接受）

- [ ] **步骤 2：构建验证**

运行：`flutter build apk --debug`（或当前平台对应的构建命令）
预期：构建成功

- [ ] **步骤 3：手动测试清单**

在设备上验证以下场景：

1. **基本持久化**：播放一首歌 → 切换播放模式为随机 → 杀掉应用 → 重新打开 → 确认 mini player 显示上次的歌曲，播放模式为随机
2. **自动播放开启**：开启自动播放 → 播放歌曲 → 杀掉应用 → 重新打开 → 确认自动播放上次歌曲
3. **自动播放关闭**：关闭自动播放 → 播放歌曲 → 杀掉应用 → 重新打开 → 确认显示上次歌曲但不自动播放
4. **单曲循环失败**：设为单曲循环 → 播放一首无法播放的歌 → 杀掉应用 → 重新打开（自动播放开启）→ 确认显示错误提示，不切歌
5. **顺序播放失败**：设为顺序播放 → 播放无法播放的歌 → 杀掉应用 → 重新打开 → 确认自动切到下一首
6. **无保存状态回退**：清除应用数据 → 开启自动播放 → 打开应用 → 确认回退到每日推荐
