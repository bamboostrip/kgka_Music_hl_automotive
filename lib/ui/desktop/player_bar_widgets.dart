import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';

/// 桌面播放条增强部件与纯逻辑：播放模式按钮、音量图标交互、进度悬停时间气泡。
///
/// 播放状态一律读写 [PlayerController] 同一字段（与全屏播放页/车机面板同源），
/// 本文件不持有播放状态；可单测的换算逻辑全部抽成顶层纯函数。

/// 音量滚轮单次步进（±5%，与 ↑/↓ 快捷键一致）。
const double kVolumeWheelStep = 0.05;

/// 取消静音但没有记忆音量时恢复的默认值。
const double kDefaultRestoreVolume = 0.5;

/// 播放模式 → 图标（与全屏播放页 `_playbackModeIcon` 同语义）。
IconData playbackModeIcon(PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.playlistLoop => Icons.repeat_rounded,
    PlaybackMode.shuffle => Icons.shuffle_rounded,
    PlaybackMode.singleLoop => Icons.repeat_one_rounded,
  };
}

/// 播放模式 → 按钮提示：显示当前模式名并附带切换提示。
String playbackModeTooltip(PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.playlistLoop => '列表循环（点击切换）',
    PlaybackMode.shuffle => '随机播放（点击切换）',
    PlaybackMode.singleLoop => '单曲循环（点击切换）',
  };
}

/// 音量 → 图标：0 视为静音、<0.5 小音量、否则大音量。
IconData volumeIconFor(double volume) {
  if (volume <= 0) return Icons.volume_off_rounded;
  return volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded;
}

/// 点击音量图标的静音/取消静音换算：
/// 当前有音量 → 静音（返回 0，并记住当前音量）；
/// 当前无声 → 取消静音（恢复记忆音量，无记忆回退默认值）。
/// 返回 `(应设置的音量, 新的记忆值)`。
(double, double?) toggleMute(double currentVolume, double? remembered) {
  if (currentVolume > 0) {
    return (0.0, currentVolume.clamp(0.0, 1.0));
  }
  final restored = (remembered ?? kDefaultRestoreVolume).clamp(0.0, 1.0);
  return (restored, remembered);
}

/// 滚轮步进后的音量：向上（scrollDelta.dy < 0）+ [step]、向下 -[step]，钳制 0..1。
double applyVolumeWheel(
  double currentVolume,
  bool scrollUp, {
  double step = kVolumeWheelStep,
}) {
  return (currentVolume + (scrollUp ? step : -step)).clamp(0.0, 1.0);
}

/// 进度条悬停横坐标 → 该位置对应的时间点；横坐标越界按两端钳制，
/// 宽度或时长非法时返回 0。
Duration positionForHover(double localX, double trackWidth, Duration duration) {
  if (trackWidth <= 0 || duration <= Duration.zero) return Duration.zero;
  final fraction = (localX / trackWidth).clamp(0.0, 1.0);
  return Duration(milliseconds: (duration.inMilliseconds * fraction).round());
}

/// 播放模式按钮：图标随模式变化，tooltip 提示当前模式（含切换提示）。
///
/// 直接调用 [PlayerController.cyclePlaybackMode]，与全屏播放页共用同一状态。
class PlayModeButton extends StatelessWidget {
  const PlayModeButton({super.key, required this.player, this.iconSize = 22});

  final PlayerController player;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: playbackModeTooltip(player.playbackMode),
      onPressed: player.cyclePlaybackMode,
      icon: Icon(playbackModeIcon(player.playbackMode), size: iconSize),
      color: Theme.of(context).colorScheme.onSurface,
    );
  }
}

/// 音量图标按钮：点击静音/取消静音（记忆静音前音量），滚轮 ±5% 微调。
///
/// 音量条拖拽仍由播放条里音量区的 Slider 负责，二者写同一音量字段。
class VolumeIconButton extends StatefulWidget {
  const VolumeIconButton({super.key, required this.player, this.iconSize = 20});

  final PlayerController player;
  final double iconSize;

  @override
  State<VolumeIconButton> createState() => _VolumeIconButtonState();
}

class _VolumeIconButtonState extends State<VolumeIconButton> {
  double? _volumeBeforeMute;

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 滚轮向上（scrollDelta.dy < 0）增大音量，向下减小。
    widget.player.setVolume(
      applyVolumeWheel(widget.player.volume, event.scrollDelta.dy < 0),
    );
  }

  void _handleTap() {
    final (volume, memory) = toggleMute(
      widget.player.volume,
      _volumeBeforeMute,
    );
    setState(() => _volumeBeforeMute = memory);
    widget.player.setVolume(volume);
  }

  @override
  Widget build(BuildContext context) {
    final volume = widget.player.volume.clamp(0.0, 1.0);
    return Tooltip(
      message: volume <= 0 ? '取消静音' : '静音',
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              volumeIconFor(volume),
              size: widget.iconSize,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 垂直音量气泡弹层入口按钮：
/// - 点击展开/收起垂直音量卡片（包含垂直滑块、百分比、静音切换按钮、向下箭头）
/// - 支持滚轮微调 ±5%
/// - 外部点击非阻塞关闭（通过 TapRegion(groupId: 'desktop_volume_popover')）
/// - 展开时高亮主题色
class VolumePopoverButton extends StatefulWidget {
  const VolumePopoverButton({
    super.key,
    required this.player,
    this.iconSize = 22,
  });

  final PlayerController player;
  final double iconSize;

  @override
  State<VolumePopoverButton> createState() => _VolumePopoverButtonState();
}

class _VolumePopoverButtonState extends State<VolumePopoverButton> {
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _link = LayerLink();
  double? _volumeBeforeMute;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onPlayerChanged);
  }

  @override
  void didUpdateWidget(covariant VolumePopoverButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayerChanged);
      widget.player.addListener(_onPlayerChanged);
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    if (_overlayController.isShowing) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    _overlayController.show();
    if (mounted) setState(() {});
  }

  void _hide() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
      if (mounted) setState(() {});
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    widget.player.setVolume(
      applyVolumeWheel(widget.player.volume, event.scrollDelta.dy < 0),
    );
  }

  void _handleMuteToggle() {
    final (newVol, mem) = toggleMute(widget.player.volume, _volumeBeforeMute);
    setState(() => _volumeBeforeMute = mem);
    widget.player.setVolume(newVol);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOpen = _overlayController.isShowing;
    final volume = widget.player.volume.clamp(0.0, 1.0);

    return TapRegion(
      groupId: 'desktop_volume_popover',
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) {
            return Stack(
              children: [
                CompositedTransformFollower(
                  link: _link,
                  targetAnchor: Alignment.topCenter,
                  followerAnchor: Alignment.bottomCenter,
                  offset: const Offset(0, -8),
                  child: TapRegion(
                    groupId: 'desktop_volume_popover',
                    onTapOutside: (_) => _hide(),
                    child: _VolumePopoverCard(
                      player: widget.player,
                      onMuteToggle: _handleMuteToggle,
                      onPointerSignal: _handlePointerSignal,
                    ),
                  ),
                ),
              ],
            );
          },
          child: Tooltip(
            message: '音量',
            child: Listener(
              onPointerSignal: _handlePointerSignal,
              child: Container(
                decoration: isOpen
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        color: colorScheme.primary.withValues(alpha: 0.08),
                      )
                    : null,
                child: IconButton(
                  onPressed: _toggle,
                  icon: Icon(volumeIconFor(volume), size: widget.iconSize),
                  color: isOpen ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 垂直音量弹出卡片（顶层垂直滑块、中层百分比、底层静音按钮、底部三角下指示箭头）。
class _VolumePopoverCard extends StatefulWidget {
  const _VolumePopoverCard({
    required this.player,
    required this.onMuteToggle,
    required this.onPointerSignal,
  });

  final PlayerController player;
  final VoidCallback onMuteToggle;
  final ValueChanged<PointerSignalEvent> onPointerSignal;

  @override
  State<_VolumePopoverCard> createState() => _VolumePopoverCardState();
}

class _VolumePopoverCardState extends State<_VolumePopoverCard> {
  double? _dragValue;

  @override
  void didUpdateWidget(covariant _VolumePopoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.player != oldWidget.player) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF262D3D) : Colors.white;
    final borderColor = colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.3 : 0.5,
    );

    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final volume = (_dragValue ?? widget.player.volume).clamp(0.0, 1.0);
        final percent = (volume * 100).round();

        return Listener(
          onPointerSignal: widget.onPointerSignal,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 178,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.4 : 0.12,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    // 顶部垂直滑块（quarterTurns: 3，下端为 0，上端为 1）
                    SizedBox(
                      height: 100,
                      width: 32,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                            activeTrackColor: colorScheme.primary,
                            thumbColor: colorScheme.primary,
                            inactiveTrackColor: colorScheme.outlineVariant
                                .withValues(alpha: 0.3),
                          ),
                          child: Slider(
                            value: volume,
                            onChanged: (val) {
                              setState(() => _dragValue = val);
                              widget.player.setVolume(val);
                            },
                            onChangeEnd: (val) {
                              widget.player.setVolume(val);
                              if (mounted) {
                                setState(() => _dragValue = null);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    // 中间音量百分比
                    Text(
                      '$percent%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    // 底部静音/取消静音按钮
                    IconButton(
                      key: const ValueKey('volume_popover_mute_button'),
                      tooltip: volume <= 0 ? '取消静音' : '静音',
                      onPressed: widget.onMuteToggle,
                      icon: Icon(
                        volumeIconFor(volume),
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -1),
                child: CustomPaint(
                  size: const Size(12, 6),
                  painter: _BeakPainter(color: bg, borderColor: borderColor),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 底部三角下箭头指示器（指向底部的音量入口按钮）
class _BeakPainter extends CustomPainter {
  const _BeakPainter({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, fillPaint);

    final borderPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(borderPath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _BeakPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderColor != borderColor;
}

/// 进度条悬停时间气泡：鼠标在 [child]（进度条）上移动时，上方跟随显示
/// 悬停位置对应的时间；离开即消失。
///
/// [showBubble] 为 false（拖拽中或无时长）时不渲染气泡，只保留子组件行为。
class HoverTimeBubble extends StatefulWidget {
  const HoverTimeBubble({
    super.key,
    required this.duration,
    required this.showBubble,
    required this.formatDuration,
    required this.child,
  });

  /// 曲目总时长，用于把悬停横坐标换算成时间。
  final Duration duration;

  /// 是否允许显示气泡（拖拽中传 false）。
  final bool showBubble;

  /// 秒数 → 文案（复用播放条的 `formatDuration`）。
  final String Function(Duration) formatDuration;

  final Widget child;

  @override
  State<HoverTimeBubble> createState() => _HoverTimeBubbleState();
}

class _HoverTimeBubbleState extends State<HoverTimeBubble> {
  double? _hoverX;

  /// 悬停时记录的子组件（进度条）实际宽度；
  /// 不能用 LayoutBuilder——进度条位于 mainAxisSize.min 的 Row 里，
  /// 其 maxWidth 约束是无界的，需要读取渲染盒真实尺寸。
  double _trackWidth = 0;

  bool get _visible =>
      widget.showBubble && widget.duration > Duration.zero && _hoverX != null;

  void _onHover(PointerEvent event) {
    final box = context.findRenderObject();
    setState(() {
      _hoverX = event.localPosition.dx;
      if (box is RenderBox && box.hasSize) {
        _trackWidth = box.size.width;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onHover: _onHover,
      onExit: (_) => setState(() => _hoverX = null),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_visible)
            Positioned(
              top: 0,
              left: _hoverX!.clamp(0.0, _trackWidth),
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                // 纯视觉反馈，不拦截进度条的手势：进度条收窄后气泡会盖住
                // 按下点，不加则拖拽手势落到气泡上导致 Slider 收不到 onChanged。
                child: IgnorePointer(
                  child: Container(
                    // 供 widget 测试定位气泡。
                    key: const ValueKey('hover_time_bubble'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      widget.formatDuration(
                        positionForHover(
                          _hoverX!,
                          _trackWidth,
                          widget.duration,
                        ),
                      ),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onInverseSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 封面悬停时展示的对角直角展开图标（截图 3 风格：右上角 ┐ + 左下角 └）。
class ExpandDetailIcon extends StatelessWidget {
  const ExpandDetailIcon({
    super.key,
    this.size = 18,
    this.color = Colors.white,
    this.strokeWidth = 2.0,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ExpandDetailPainter(color: color, strokeWidth: strokeWidth),
    );
  }
}

class _ExpandDetailPainter extends CustomPainter {
  const _ExpandDetailPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final p = strokeWidth / 2;
    final arm = w * 0.42;

    // 左下角 └
    final pathBottomLeft = Path()
      ..moveTo(p, h - p - arm)
      ..lineTo(p, h - p)
      ..lineTo(p + arm, h - p);
    canvas.drawPath(pathBottomLeft, paint);

    // 右上角 ┐
    final pathTopRight = Path()
      ..moveTo(w - p - arm, p)
      ..lineTo(w - p, p)
      ..lineTo(w - p, p + arm);
    canvas.drawPath(pathTopRight, paint);
  }

  @override
  bool shouldRepaint(covariant _ExpandDetailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
