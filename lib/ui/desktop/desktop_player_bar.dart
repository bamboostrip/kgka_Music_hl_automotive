import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../pages/comment_page.dart';
import '../player/player_route.dart';
import '../widgets/artwork.dart';
import '../widgets/audio_effects_sheet.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/climax_slider_track.dart';
import '../widgets/desktop_anchored_menu.dart';
import '../widgets/desktop_queue_panel.dart';
import '../widgets/song_action_sheets.dart';
import '../widgets/toast.dart';
import 'player_bar_widgets.dart';

/// 秒数 → `mm:ss`（≥1h 时 `h:mm:ss`）。
String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// 窄窗断点：<1100 收起次要按钮 + 音量条只留图标（滚轮/点击仍可调）。
const double kPlayerBarCompactBreakpoint = 1100;

/// 左区固定宽度（封面 + 曲名 + 操作入口）。
const double kPlayerBarLeftWidth = 300;
const double kPlayerBarLeftWidthCompact = 232;

/// 桌面底部播放栏：QQ 音乐 PC 式左/中/右三段布局，视觉沿用本项目主题。
///
/// - 左：封面/曲目信息（悬停浮出放大图标，点击进播放页）+ 喜欢/评论/下载/更多（窄窗只留喜欢）。
/// - 中：上层播放控制（居中）+ 下层进度条（Expanded 吃满剩余宽度）。
/// - 右：音质 + 音效(?) + 音量 + 桌面词(?) + 队列。
///
/// 无歌曲时保持占位布局（高度稳定，不随播放状态跳变）。
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({
    super.key,
    required this.player,
    required this.auth,
  });

  final PlayerController player;
  final AuthController auth;

  void _openPlayerPage(BuildContext context) {
    if (player.currentSong == null) return;
    PlayerPageRoute.open(context, player: player, auth: auth);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final song = player.currentSong;
        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2433) : Colors.white,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: .5),
                width: 1,
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < kPlayerBarCompactBreakpoint;
              final leftWidth =
                  compact ? kPlayerBarLeftWidthCompact : kPlayerBarLeftWidth;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 12),
                  // —— 左：歌曲信息 + 操作入口 ——
                  SizedBox(
                    width: leftWidth,
                    child: Row(
                      children: [
                        _SongInfo(
                          song: song,
                          colorScheme: colorScheme,
                          onTap: () => _openPlayerPage(context),
                        ),
                        const SizedBox(width: 4),
                        _SongActionRail(
                          player: player,
                          auth: auth,
                          song: song,
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                  // —— 中：控制（上）+ 进度（下），Expanded 吃满剩余宽度 ——
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      // 紧凑点击目标：中间列是控制+进度双层叠放，默认 48px
                      // 点击目标会撑爆 80px 底栏，这里收成桌面鼠标友好的
                      // 小目标（保留图标尺寸，只收内边距）。
                      child: IconButtonTheme(
                        data: IconButtonThemeData(
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PlayModeButton(player: player),
                                const SizedBox(width: 20),
                                IconButton(
                                  tooltip: '上一首',
                                  onPressed:
                                      song == null ? null : player.previous,
                                  icon: const Icon(
                                    Icons.skip_previous_rounded,
                                    size: 28,
                                  ),
                                  color: colorScheme.onSurface,
                                ),
                                const SizedBox(width: 20),
                                IconButton(
                                  tooltip: player.isPlaying ? '暂停' : '播放',
                                  onPressed: player.isPreparing || song == null
                                      ? null
                                      : player.togglePlay,
                                  icon: Icon(
                                    player.isPlaying
                                        ? Icons.pause_circle_rounded
                                        : Icons.play_circle_rounded,
                                    size: 36,
                                  ),
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 20),
                                IconButton(
                                  tooltip: '下一首',
                                  onPressed: song == null ? null : player.next,
                                  icon: const Icon(
                                    Icons.skip_next_rounded,
                                    size: 28,
                                  ),
                                  color: colorScheme.onSurface,
                                ),
                              ],
                            ),
                            // 进度区（拖拽中显示拖拽位置，松手 seek）。
                            // 无歌时不渲染，但中间列仍由控制行撑住，底栏高度不变。
                            if (song != null) ...[
                              Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 440),
                                  child: _ProgressBar(player: player),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // —— 右：功能区 ——
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 音质切换
                      _AudioQualityButton(
                        key: const ValueKey(
                          'desktop_audio_quality_button',
                        ),
                        player: player,
                      ),
                      const SizedBox(width: 8),
                      // 音效（仅受支持平台渲染，不支持时不占位）
                      _EffectsButton(player: player),
                      // 音量（窄窗只留图标，宽窗带滑杆）
                      _VolumeControl(
                        player: player,
                        showSlider: !compact,
                      ),
                      const SizedBox(width: 8),
                      // 桌面歌词开关（仅支持桌面歌词的平台渲染）
                      if (player.isDesktopLyricsSupported) ...[
                        _DesktopLyricsButton(player: player, song: song),
                        const SizedBox(width: 4),
                      ],
                      // 队列（PC：锚定在按钮上方的面板，替代移动端底部弹层）
                      Builder(
                        builder: (buttonContext) => IconButton(
                          tooltip: '播放队列',
                          onPressed: song == null
                              ? null
                              : () => showDesktopQueuePanel(
                                  buttonContext,
                                  player,
                                ),
                          icon: const Icon(
                            Icons.queue_music_rounded,
                            size: 26,
                          ),
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// 左区：封面 + 曲名/歌手。悬停封面或歌名时，封面上浮出半透明蒙层 +
/// 放大图标提示可进入播放页，点击整个区域进入。
@visibleForTesting
class SongInfo extends StatefulWidget {
  const SongInfo({
    super.key,
    required this.song,
    required this.colorScheme,
    required this.onTap,
  });

  final Song? song;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  State<SongInfo> createState() => _SongInfoState();
}

typedef _SongInfo = SongInfo;

class _SongInfoState extends State<SongInfo> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    return Flexible(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: song == null ? '' : '展开歌曲详情页',
          child: InkWell(
            onTap: song == null ? null : widget.onTap,
            borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    children: [
                      Artwork(
                        url: song?.coverUrl,
                        size: 48,
                        borderRadius: 8,
                      ),
                      if (_hovered && song != null)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: ExpandDetailIcon(size: 20),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? '尚未播放',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: song == null
                              ? widget.colorScheme.onSurfaceVariant
                              : widget.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song?.artist ?? '去挑一首喜欢的歌吧',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// 可选能力的安全读取：单测 fake 未实现这些成员时会抛，
/// 此时按“能力不可用”降级渲染而不是崩溃。
bool? _safeIsLiked(AuthController auth, Song song) {
  try {
    return auth.isLiked(song);
  } catch (_) {
    return null;
  }
}

dynamic _safeDownloadController(PlayerController player) {
  try {
    return player.downloadController;
  } catch (_) {
    return null;
  }
}

bool _safeIsAudioEffectsSupported(PlayerController player) {
  try {
    return player.isAudioEffectsSupported;
  } catch (_) {
    return false;
  }
}

dynamic _safeApi(PlayerController player) {
  try {
    return player.api;
  } catch (_) {
    return null;
  }
}

/// 左区：喜欢/评论/下载/更多。无歌时全部禁用，窄窗只留喜欢。
class _SongActionRail extends StatelessWidget {
  const _SongActionRail({
    required this.player,
    required this.auth,
    required this.song,
    required this.compact,
  });

  final PlayerController player;
  final AuthController auth;
  final Song? song;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.onSurfaceVariant;
    const iconSize = 19.0;

    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final liked = song == null ? null : _safeIsLiked(auth, song!);
        // 与播放页统一：仅酷狗源可喜欢（喜欢走歌单 fileId 体系）。
        final likeEnabled =
            song != null && song!.source == SongSource.kugou && liked != null;
        final isLiked = liked == true;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: isLiked ? '取消喜欢' : '喜欢',
              onPressed: !likeEnabled
                  ? null
                  : () {
                      try {
                        auth.toggleLike(song!);
                      } catch (_) {
                        Toast.error('收藏失败，请重试');
                      }
                    },
              icon: Icon(
                isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: iconSize,
              ),
              color: isLiked ? colorScheme.secondary : iconColor,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 30,
                height: 30,
              ),
            ),
            if (!compact) ...[
              _CommentButton(
                player: player,
                song: song,
                iconColor: iconColor,
                iconSize: iconSize,
              ),
              _DownloadButton(
                player: player,
                song: song,
                iconColor: iconColor,
                iconSize: iconSize,
              ),
              IconButton(
                tooltip: '添加到歌单',
                onPressed: song == null
                    ? null
                    : () => showAddToPlaylistSheet(
                        context: context,
                        auth: auth,
                        song: song!,
                      ),
                icon: const Icon(
                  Icons.playlist_add_rounded,
                  size: iconSize,
                ),
                color: iconColor,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CommentButton extends StatelessWidget {
  const _CommentButton({
    required this.player,
    required this.song,
    required this.iconColor,
    required this.iconSize,
  });

  final PlayerController player;
  final Song? song;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final api = _safeApi(player);
    // 与播放页统一：仅酷狗源有评论。
    final enabled = song != null &&
        song!.source == SongSource.kugou &&
        api != null &&
        (song!.albumAudioId ?? song!.id).isNotEmpty;
    return IconButton(
      tooltip: enabled ? '评论' : '暂无评论',
      onPressed: !enabled
          ? null
          : () {
              final mixsongid = song!.albumAudioId ?? song!.id;
              if (mixsongid.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CommentPage(
                    api: api,
                    mixsongid: mixsongid,
                  ),
                ),
              );
            },
      icon: const Icon(Icons.chat_bubble_outline_rounded),
      iconSize: iconSize,
      color: iconColor,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.player,
    required this.song,
    required this.iconColor,
    required this.iconSize,
  });

  final PlayerController player;
  final Song? song;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final ctrl = _safeDownloadController(player);
    if (ctrl == null) {
      return IconButton(
        tooltip: '下载',
        onPressed: null,
        icon: const Icon(Icons.download_rounded),
        iconSize: iconSize,
        color: iconColor,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      );
    }
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        bool downloaded = false;
        try {
          downloaded = song == null ? false : ctrl.isDownloaded(song!);
        } catch (_) {
          downloaded = false;
        }
        return IconButton(
          tooltip: downloaded ? '已下载' : '下载',
          onPressed: song == null
              ? null
              : () {
                  if (downloaded) {
                    Toast.info('歌曲已下载');
                  } else {
                    try {
                      ctrl.download(song!, player.audioQuality);
                      Toast.success('已加入下载队列');
                    } catch (_) {
                      Toast.error('下载失败，请重试');
                    }
                  }
                },
          icon: Icon(
            downloaded
                ? Icons.download_done_rounded
                : Icons.download_rounded,
          ),
          iconSize: iconSize,
          color: downloaded
              ? Theme.of(context).colorScheme.primary
              : iconColor,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        );
      },
    );
  }
}

/// 右区：音效入口。仅受支持平台渲染，不支持时不占位。
class _EffectsButton extends StatelessWidget {
  const _EffectsButton({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        if (!_safeIsAudioEffectsSupported(player)) {
          return const SizedBox.shrink();
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '音效',
              onPressed: () => showAudioEffectsSheet(
                context: context,
                player: player,
              ),
              icon: const Icon(Icons.graphic_eq_rounded, size: 22),
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}

/// 右区：桌面歌词开关（三态：锁定/开启/关闭）。
class _DesktopLyricsButton extends StatelessWidget {
  const _DesktopLyricsButton({required this.player, required this.song});

  final PlayerController player;
  final Song? song;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final enabled = player.desktopLyricsEnabled;
        final locked = player.desktopLyricsLocked;
        final String tooltip;
        final IconData iconData;
        final Color color;
        final VoidCallback? onPressed;

        if (enabled && locked) {
          tooltip = '桌面歌词已锁定，点击一键解锁';
          iconData = Icons.lock_rounded;
          color = colorScheme.primary;
          onPressed =
              song == null ? null : () => player.unlockDesktopLyrics();
        } else if (enabled) {
          tooltip = '关闭桌面歌词';
          iconData = Icons.lyrics_rounded;
          color = colorScheme.primary;
          onPressed = song == null
              ? null
              : () => player.setDesktopLyricsEnabled(false);
        } else {
          tooltip = '开启桌面歌词';
          iconData = Icons.lyrics_outlined;
          color = colorScheme.onSurface;
          onPressed = song == null
              ? null
              : () => player.setDesktopLyricsEnabled(true);
        }

        return IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(iconData, size: 26),
          color: color,
        );
      },
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.player});

  final PlayerController player;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.player.positionListenable,
      builder: (context, position, _) {
        final durationMs = widget.player.duration.inMilliseconds;
        final progress = _dragValue ??
            (durationMs > 0
                ? (position.inMilliseconds / durationMs).clamp(0.0, 1.0)
                : 0.0);
        final shownPosition = _dragValue != null && durationMs > 0
            ? Duration(milliseconds: (durationMs * _dragValue!).round())
            : position;
        return Row(
          children: [
            Text(
              formatDuration(shownPosition),
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            // 中间列 Expanded：进度条吃满左/右区之外的全部剩余宽度。
            // 悬停显示该位置时间气泡；拖拽中不显示（拖拽本身有位置反馈）。
            // 高度收到 28（桌面鼠标够用）：Slider 默认触控高度 48，
            // 双层叠放时会撑爆 80px 底栏。
            Expanded(
              child: SizedBox(
                height: 28,
                child: HoverTimeBubble(
                  duration: widget.player.duration,
                  showBubble: _dragValue == null && durationMs > 0,
                  formatDuration: formatDuration,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 8),
                      // 高潮起始标记（与播放页同一套轨道，多端数据同源）。
                      trackShape: ClimaxSliderTrackShape(
                        climaxStart: climaxStartFraction(
                          climax: widget.player.climax,
                          durationMs: durationMs,
                        ),
                        markerColor:
                            colorScheme.primary.withValues(alpha: .45),
                      ),
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: durationMs > 0
                          ? (value) => setState(() => _dragValue = value)
                          : null,
                      onChangeEnd: durationMs > 0
                          ? (value) async {
                              try {
                                await widget.player.seek(
                                  Duration(
                                    milliseconds:
                                        (durationMs * value).round(),
                                  ),
                                );
                              } catch (_) {
                                Toast.error('定位失败，请重试');
                              }
                              if (mounted) {
                                setState(() => _dragValue = null);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDuration(widget.player.duration),
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.player, this.showSlider = true});

  final PlayerController player;
  final bool showSlider;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        // 拖拽中显示拖拽值，其余时刻跟随 player（快捷键/其他入口改动即时同步）。
        final volume =
            (_dragValue ?? widget.player.volume).clamp(0.0, 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 点击静音/取消静音（记忆静音前音量），图标区滚轮 ±5%。
            VolumeIconButton(player: widget.player),
            if (widget.showSlider)
              SizedBox(
                width: 96,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: volume,
                    onChanged: (value) {
                      setState(() => _dragValue = value);
                      widget.player.setVolume(value);
                    },
                    onChangeEnd: (value) {
                      widget.player.setVolume(value);
                      setState(() => _dragValue = null);
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AudioQualityButton extends StatelessWidget {
  const _AudioQualityButton({super.key, required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final song = player.currentSong;
        final quality = player.audioQuality;
        final enabled = song != null;
        final colorScheme = Theme.of(context).colorScheme;
        final isLossless = quality == AudioQuality.lossless;
        final label = switch (quality) {
          AudioQuality.standard => '标准',
          AudioQuality.high => '高品',
          AudioQuality.lossless => '无损',
        };
        final tooltip = '音质：${quality.label} (${quality.badge}) - 点击切换';

        final Color foregroundColor;
        final Color borderColor;
        if (!enabled) {
          foregroundColor = colorScheme.onSurface.withValues(alpha: .38);
          borderColor = colorScheme.outlineVariant.withValues(alpha: .38);
        } else if (isLossless) {
          foregroundColor = colorScheme.primary;
          borderColor = colorScheme.primary.withValues(alpha: .6);
        } else {
          foregroundColor = colorScheme.onSurfaceVariant;
          borderColor = colorScheme.outlineVariant;
        }

        return Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: borderColor, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              mouseCursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              hoverColor:
                  (isLossless ? colorScheme.primary : colorScheme.onSurface)
                      .withValues(alpha: 0.08),
              onTap: enabled
                  ? () async {
                      final anchor = anchorAboveRight(context);
                      final picked = await showAudioQualitySheet(
                        context: context,
                        selected: player.audioQuality,
                        title: '切换音质',
                        subtitle: '会重新加载当前歌曲并尽量保持播放进度',
                        anchor: anchor,
                      );
                      if (picked != null) {
                        await player.setAudioQuality(
                          picked,
                          reloadCurrent: true,
                        );
                        Toast.success('已切换到 ${picked.label}');
                      }
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLossless) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: foregroundColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'SQ',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: foregroundColor,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: foregroundColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
