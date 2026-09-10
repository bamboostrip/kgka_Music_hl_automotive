import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../pages/artist_detail_page.dart';
import '../pages/comment_page.dart';
import '../player/player_route.dart';
import '../widgets/artwork.dart';
import '../widgets/audio_effects_sheet.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/climax_slider_track.dart';
import '../widgets/desktop_anchored_menu.dart';
import '../widgets/desktop_queue_panel.dart';
import '../widgets/marquee_text.dart';
import '../widgets/playback_speed_sheet.dart';
import '../widgets/sleep_timer_sheet.dart';
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

/// 窄窗断点：<1100 左区收窄（按钮间距随之收紧，操作按钮不隐藏）。
const double kPlayerBarCompactBreakpoint = 1100;

/// 左区固定宽度（封面 + 曲名 + 操作入口）。
const double kPlayerBarLeftWidth = 300;
const double kPlayerBarLeftWidthCompact = 232;

/// 桌面底部播放栏：QQ 音乐 PC 式左/中/右三段布局，视觉沿用本项目主题。
///
/// - 左：封面/曲目信息（悬停浮出放大图标，点击进播放页）+ 喜欢/评论/下载/更多（窄窗只留喜欢）。
/// - 中：上层播放控制（居中，含播放模式、上一首、播放/暂停、下一首、音量气泡）+ 下层进度条（Expanded 吃满剩余宽度）。
/// - 右：音质 + 音效(?) + 桌面词(?) + 队列。
///
/// 无歌曲时保持占位布局（高度稳定，不随播放状态跳变）。
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({
    super.key,
    required this.player,
    required this.auth,
    this.onOpenPlayerPage,
    this.onOpenComment,
    this.onOpenArtist,
  });

  final PlayerController player;
  final AuthController auth;
  final VoidCallback? onOpenPlayerPage;

  /// 打开评论页。桌面由 shell 传入，推入内容区 Navigator（保留侧栏）；
  /// 未传时退回根 Navigator（全屏，移动端语义）。
  final ValueChanged<String>? onOpenComment;

  /// 打开歌手页。桌面由 shell 传入，推入内容区 Navigator（保留侧栏）；
  /// 未传时退回根 Navigator（全屏）。
  final ValueChanged<ArtistRef>? onOpenArtist;

  void _openPlayerPage(BuildContext context) {
    if (player.currentSong == null) return;
    if (onOpenPlayerPage != null) {
      onOpenPlayerPage!();
      return;
    }
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
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: song == null ? null : () => _openPlayerPage(context),
          child: MouseRegion(
            cursor: song == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: Container(
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
              final leftWidth = compact
                  ? kPlayerBarLeftWidthCompact
                  : kPlayerBarLeftWidth;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 12),
                  // —— 左：歌曲信息 + 操作入口 ——
                  SizedBox(
                    width: leftWidth,
                    child: SongInfo(
                      player: player,
                      auth: auth,
                      song: song,
                      colorScheme: colorScheme,
                      onTap: () => _openPlayerPage(context),
                      onOpenComment: onOpenComment,
                      onOpenArtist: onOpenArtist,
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
                                  onPressed: song == null
                                      ? null
                                      : player.previous,
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
                                const SizedBox(width: 20),
                                VolumePopoverButton(
                                  key: const ValueKey(
                                    'desktop_volume_popover_button',
                                  ),
                                  player: player,
                                ),
                              ],
                            ),
                            // 进度区（拖拽中显示拖拽位置，松手 seek）。
                            // 无歌时不渲染，但中间列仍由控制行撑住，底栏高度不变。
                            if (song != null) ...[
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 440,
                                  ),
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
                        key: const ValueKey('desktop_audio_quality_button'),
                        player: player,
                      ),
                      const SizedBox(width: 8),
                      // 音效（仅受支持平台渲染，不支持时不占位）
                      _EffectsButton(player: player),
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
                          icon: const Icon(Icons.queue_music_rounded, size: 26),
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
        ),
      ),
    );
  },
);
  }
}

/// 左区：封面 + 曲名/歌手跑马灯 + 操作按钮行。
/// 悬停封面时浮出半透明蒙层 + 放大图标提示可进入播放页，点击进入。
@visibleForTesting
class SongInfo extends StatefulWidget {
  const SongInfo({
    super.key,
    required this.song,
    required this.colorScheme,
    required this.onTap,
    this.player,
    this.auth,
    this.onOpenComment,
    this.onOpenArtist,
  });

  final Song? song;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final PlayerController? player;
  final AuthController? auth;
  final ValueChanged<String>? onOpenComment;
  final ValueChanged<ArtistRef>? onOpenArtist;

  @override
  State<SongInfo> createState() => _SongInfoState();
}


class _SongInfoState extends State<SongInfo> {
  bool _coverHovered = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final colorScheme = widget.colorScheme;
    final iconColor = colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget content = Row(
          children: [
            // 48x48 封面，悬停展示 ExpandDetailIcon 和 tooltip
            MouseRegion(
              onEnter: (_) {
                if (mounted) setState(() => _coverHovered = true);
              },
              onExit: (_) {
                if (mounted) setState(() => _coverHovered = false);
              },
              child: Tooltip(
                message: song == null ? '' : '展开歌曲详情页',
                child: InkWell(
                  onTap: song == null ? null : widget.onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      children: [
                        Artwork(url: song?.coverUrl, size: 48, borderRadius: 8),
                        if (_coverHovered && song != null)
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
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 右侧纵向居中 Column：
            // Row 1: MarqueeText（歌名粗体 onSurface - 歌手常规 onSurfaceVariant）
            // Row 2: 操作按钮行 [LikeButton, SizedBox(width: 8), CommentButton, SizedBox(width: 8), SongMoreButton]
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: song == null ? null : widget.onTap,
                    child: MouseRegion(
                      cursor: song == null
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: MarqueeText(
                        textSpan: TextSpan(
                          children: [
                            TextSpan(
                              text: song?.title ?? '尚未播放',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: song == null
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                              ),
                            ),
                            if (song != null && song.artist.isNotEmpty)
                              TextSpan(
                                text: ' - ${song.artist}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LikeButton(
                          auth: widget.auth,
                          song: song,
                          iconColor: iconColor,
                          activeColor: colorScheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        _CommentButton(
                          player: widget.player,
                          song: song,
                          iconColor: iconColor,
                          onOpenComment: widget.onOpenComment,
                        ),
                        const SizedBox(width: 8),
                        SongMoreButton(
                          player: widget.player,
                          auth: widget.auth,
                          song: song,
                          onOpenArtist: widget.onOpenArtist,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (!constraints.hasBoundedWidth) {
          content = SizedBox(width: kPlayerBarLeftWidth, child: content);
        }
        return content;
      },
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

String _safePlaybackSpeedLabel(PlayerController player) {
  try {
    return player.playbackSpeedLabel;
  } catch (_) {
    return '1.0x';
  }
}

String? _safeSleepTimerSubtitle(PlayerController player) {
  try {
    if (player.isSleepTimerActive) {
      final rem = player.sleepTimerRemaining;
      final text = formatSleepRemaining(rem);
      return text.isNotEmpty ? '剩余 $text' : null;
    }
    if (player.isSleepFinishCurrentSong) {
      return '播完歌曲后停止';
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 桌面级联二级：倍速档位。
List<SongSheetAction> _speedSubmenu(PlayerController player) {
  final current = snapToPlaybackSpeed(player.playbackSpeed);
  return [
    for (final step in kPlaybackSpeedSteps)
      SongSheetAction(
        icon: Icons.speed_rounded,
        title: formatPlaybackSpeed(step),
        selected: step == current,
        onTap: () => player.setPlaybackSpeed(step),
      ),
    if (current != 1.0)
      SongSheetAction(
        icon: Icons.restart_alt_rounded,
        title: '恢复默认',
        onTap: () => player.setPlaybackSpeed(1.0),
      ),
  ];
}

/// 桌面级联二级：定时选项。
List<SongSheetAction> _sleepTimerSubmenu(PlayerController player) {
  final finishSong =
      player.isSleepFinishCurrentSong || player.sleepFinishCurrentSongOption;
  final isActive = player.isSleepTimerActive || player.isSleepFinishCurrentSong;

  SongSheetAction durationAction(String label, Duration d) => SongSheetAction(
    icon: Icons.schedule_rounded,
    title: label,
    onTap: () {
      // 调用时再读偏好，避免菜单构建时捕获过期的 finishSong。
      final finish =
          player.isSleepFinishCurrentSong ||
          player.sleepFinishCurrentSongOption;
      if (finish) {
        player.setSleepTimerFinishSong(d);
      } else {
        player.setSleepTimer(d);
      }
    },
  );

  return [
    SongSheetAction(
      icon: Icons.queue_play_next_rounded,
      // 短文案适配窄菜单；悬浮出完整语义。
      title: '播完这首再停',
      tooltip: '定时结束后，等当前歌曲播完再暂停',
      selected: finishSong,
      onTap: () => player.updateSleepTimerOption(!finishSong),
    ),
    durationAction('15 分钟', const Duration(minutes: 15)),
    durationAction('30 分钟', const Duration(minutes: 30)),
    durationAction('45 分钟', const Duration(minutes: 45)),
    durationAction('60 分钟', const Duration(minutes: 60)),
    durationAction('90 分钟', const Duration(minutes: 90)),
    if (isActive)
      SongSheetAction(
        icon: Icons.timer_off_outlined,
        title: '关闭定时',
        danger: true,
        onTap: player.cancelSleepTimer,
      ),
  ];
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.auth,
    required this.song,
    required this.iconColor,
    required this.activeColor,
  });

  final AuthController? auth;
  final Song? song;
  final Color iconColor;
  final Color activeColor;
  static const double _iconSize = 18.0;

  @override
  Widget build(BuildContext context) {
    if (auth == null) {
      return IconButton(
        tooltip: '喜欢',
        onPressed: null,
        icon: const Icon(Icons.favorite_border_rounded),
        iconSize: _iconSize,
        color: iconColor,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      );
    }
    return AnimatedBuilder(
      animation: auth!,
      builder: (context, _) {
        final liked = song == null ? null : _safeIsLiked(auth!, song!);
        final likeEnabled =
            song != null && song!.source == SongSource.kugou && liked != null;
        final isLiked = liked == true;
        return IconButton(
          tooltip: isLiked ? '取消喜欢' : '喜欢',
          onPressed: !likeEnabled
              ? null
              : () {
                  try {
                    auth!.toggleLike(song!);
                  } catch (_) {
                    Toast.error('收藏失败，请重试');
                  }
                },
          icon: Icon(
            isLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
          iconSize: _iconSize,
          color: isLiked ? activeColor : iconColor,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
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
    this.onOpenComment,
  });

  final PlayerController? player;
  final Song? song;
  final Color iconColor;
  final ValueChanged<String>? onOpenComment;
  static const double _iconSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final api = player == null ? null : _safeApi(player!);
    final enabled =
        song != null &&
        song!.source == SongSource.kugou &&
        (api != null || onOpenComment != null) &&
        (song!.albumAudioId ?? song!.id).isNotEmpty;
    return IconButton(
      tooltip: enabled ? '评论' : '暂无评论',
      onPressed: !enabled
          ? null
          : () {
              final mixsongid = song!.albumAudioId ?? song!.id;
              if (mixsongid.isEmpty) return;
              final openComment = onOpenComment;
              if (openComment != null) {
                openComment(mixsongid);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CommentPage(api: api, mixsongid: mixsongid),
                ),
              );
            },
      icon: const Icon(Icons.chat_bubble_outline_rounded),
      iconSize: _iconSize,
      color: iconColor,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    );
  }
}

@visibleForTesting
class SongMoreButton extends StatefulWidget {
  const SongMoreButton({
    super.key,
    required this.player,
    required this.auth,
    required this.song,
    this.iconSize = 18.0,
    this.onOpenArtist,
  });

  final PlayerController? player;
  final AuthController? auth;
  final Song? song;
  final double iconSize;
  final ValueChanged<ArtistRef>? onOpenArtist;

  @override
  State<SongMoreButton> createState() => _SongMoreButtonState();
}

class _SongMoreButtonState extends State<SongMoreButton> {
  bool _isOpen = false;

  Future<void> _openMenu(BuildContext buttonContext) async {
    final s = widget.song;
    if (s == null) return;
    final p = widget.player;
    final a = widget.auth;
    final ctrl = p == null ? null : _safeDownloadController(p);
    bool downloaded = false;
    if (ctrl != null) {
      try {
        downloaded = ctrl.isDownloaded(s);
      } catch (_) {
        downloaded = false;
      }
    }

    // 二级菜单与主菜单共用同一锚点（更多按钮上方）。
    final menuAnchor = anchorAbove(buttonContext);

    final actions = <SongSheetAction>[
      // 正在播放栏的「...」是当前歌曲：无需「下一首播放」（无意义）。
      if (a != null)
        SongSheetAction(
          icon: Icons.playlist_add_rounded,
          title: '添加到歌单',
          onTap: () => showAddToPlaylistSheet(
            context: buttonContext,
            auth: a,
            song: s,
          ),
        ),
      if (p != null)
        SongSheetAction(
          icon: Icons.auto_awesome_rounded,
          title: '试听高潮',
          subtitle: '播放歌曲高潮片段',
          onTap: () async {
            try {
              final ok = await p.playClimaxPreview();
              if (!ok) Toast.error('暂无高潮片段');
            } catch (_) {
              Toast.error('暂无高潮片段');
            }
          },
        ),
      if (p != null)
        SongSheetAction(
          icon: Icons.speed_rounded,
          title: '倍速播放',
          subtitle: _safePlaybackSpeedLabel(p),
          // 桌面走二级菜单；移动端仍弹底部面板。
          onTap: () => showPlaybackSpeedSheet(
            context: buttonContext,
            player: p,
          ),
          submenu: _speedSubmenu(p),
        ),
      if (p != null)
        SongSheetAction(
          icon: Icons.bedtime_rounded,
          title: '定时播放',
          subtitle: _safeSleepTimerSubtitle(p),
          onTap: () => showSleepTimerSheet(
            context: buttonContext,
            player: p,
          ),
          submenu: _sleepTimerSubmenu(p),
        ),
      if (ctrl != null && p != null)
        SongSheetAction(
          icon: downloaded
              ? Icons.download_done_rounded
              : Icons.download_rounded,
          title: downloaded ? '已下载' : '下载',
          onTap: () {
            if (downloaded) {
              Toast.info('歌曲已下载');
            } else {
              try {
                ctrl.download(s, p.audioQuality);
                Toast.success('已加入下载队列');
              } catch (_) {
                Toast.error('下载失败，请重试');
              }
            }
          },
        ),
      if (s.artist.isNotEmpty)
        SongSheetAction(
          icon: Icons.person_rounded,
          title: '查看歌手',
          onTap: () async {
            final openArtist = widget.onOpenArtist;
            final artist = s.artists.firstWhere(
              (item) => item.name.isNotEmpty,
              orElse: () => ArtistRef(
                id: '',
                name: s.artist,
              ),
            );
            if (openArtist != null && artist.name.isNotEmpty) {
              openArtist(artist);
              return;
            }
            final api = p == null ? null : _safeApi(p);
            if (api != null && a != null && p != null && artist.name.isNotEmpty) {
              // 兜底：未注入内容区回调时仍可打开（整窗全屏）。
              Navigator.of(buttonContext).push(
                MaterialPageRoute(
                  builder: (_) => ArtistDetailPage(
                    api: api,
                    auth: a,
                    artist: artist,
                    player: p,
                  ),
                ),
              );
            } else {
              await Clipboard.setData(
                ClipboardData(text: s.artist),
              );
              Toast.success('已复制歌手名：${s.artist}');
            }
          },
        ),
      SongSheetAction(
        icon: Icons.copy_rounded,
        title: '复制歌曲信息',
        onTap: () async {
          final text = '${s.title} - ${s.artist}';
          await Clipboard.setData(ClipboardData(text: text));
          Toast.success('已复制歌曲信息');
        },
      ),
    ];

    await showSongActionSheet(
      context: buttonContext,
      song: s,
      actions: actions,
      anchor: menuAnchor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = widget.song != null;
    final defaultColor = colorScheme.onSurfaceVariant;
    final activeColor = colorScheme.primary;
    final currentColor = !enabled
        ? defaultColor.withValues(alpha: 0.38)
        : (_isOpen ? activeColor : defaultColor);

    return Builder(
      builder: (buttonContext) {
        return IconButton(
          key: const ValueKey('desktop_song_more_button'),
          tooltip: '更多操作',
          iconSize: widget.iconSize,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          color: currentColor,
          onPressed: !enabled
              ? null
              : () async {
                  setState(() => _isOpen = true);
                  try {
                    await _openMenu(buttonContext);
                  } finally {
                    if (mounted) {
                      setState(() => _isOpen = false);
                    }
                  }
                },
          icon: Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: currentColor,
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.more_horiz_rounded,
              size: 13,
              color: currentColor,
            ),
          ),
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
              onPressed: () =>
                  showAudioEffectsSheet(context: context, player: player),
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
          onPressed = song == null ? null : () => player.unlockDesktopLyrics();
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
        final progress =
            _dragValue ??
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
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 8,
                      ),
                      // 高潮起始标记（与播放页同一套轨道，多端数据同源）。
                      trackShape: ClimaxSliderTrackShape(
                        climaxStart: climaxStartFraction(
                          climax: widget.player.climax,
                          durationMs: durationMs,
                        ),
                        markerColor: colorScheme.primary.withValues(alpha: .45),
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
                                    milliseconds: (durationMs * value).round(),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
