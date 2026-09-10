import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../form_factor.dart';
import 'desktop_anchored_menu.dart';

/// 倍速档位：滑块与标签共用的唯一事实来源。
const List<double> kPlaybackSpeedSteps = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
const double kMinPlaybackSpeed = 0.5;
const double kMaxPlaybackSpeed = 3.0;

String formatPlaybackSpeed(double value) {
  if (value == value.roundToDouble()) return '${value.round()}x';
  return '${value}x';
}

/// 吸附到最近的倍速档位。
double snapToPlaybackSpeed(double raw) {
  var closest = kPlaybackSpeedSteps.first;
  var minDist = (raw - closest).abs();
  for (final step in kPlaybackSpeedSteps.skip(1)) {
    final dist = (raw - step).abs();
    if (dist < minDist) {
      minDist = dist;
      closest = step;
    }
  }
  return closest;
}

Future<double?> showPlaybackSpeedSheet({
  required BuildContext context,
  required PlayerController player,
}) {
  if (isDesktopFormFactor) {
    // 桌面形态用居中小窗，替代全宽底部弹层。
    return showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _PlaybackSpeedSheet(player: player, inDialog: true),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      return _PlaybackSpeedSheet(player: player, inDialog: false);
    },
  );
}

/// PC 二级菜单：倍速档位列表（播放栏「更多」菜单二级进入，不弹窗）。
Future<void> showDesktopPlaybackSpeedMenu({
  required BuildContext context,
  required Offset anchor,
  required PlayerController player,
}) {
  return showDesktopAnchoredMenu<void>(
    context: context,
    anchor: anchor,
    builder: (menuContext) {
      final current = snapToPlaybackSpeed(player.playbackSpeed);
      return DesktopPopupMenuPanel(
        title: '倍速播放',
        width: 180,
        children: [
          for (final step in kPlaybackSpeedSteps)
            DesktopPopupMenuItem(
              label: formatPlaybackSpeed(step),
              selected: step == current,
              onTap: () {
                Navigator.of(menuContext).pop();
                player.setPlaybackSpeed(step);
              },
            ),
          if (current != 1.0)
            DesktopPopupMenuItem(
              label: '恢复默认',
              onTap: () {
                Navigator.of(menuContext).pop();
                player.setPlaybackSpeed(1.0);
              },
            ),
        ],
      );
    },
  );
}

class _PlaybackSpeedSheet extends StatefulWidget {
  const _PlaybackSpeedSheet({required this.player, required this.inDialog});

  final PlayerController player;
  final bool inDialog;

  @override
  State<_PlaybackSpeedSheet> createState() => _PlaybackSpeedSheetState();
}

class _PlaybackSpeedSheetState extends State<_PlaybackSpeedSheet> {
  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = snapToPlaybackSpeed(widget.player.playbackSpeed);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.speed_rounded, color: colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              '倍速播放',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '调整音乐播放速度',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            formatPlaybackSpeed(_speed),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: _speed == 1.0
                  ? colorScheme.onSurface
                  : colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        PlaybackSpeedScale(
          value: _speed,
          onChanged: (step) => setState(() => _speed = step),
          onChangeEnd: (step) => widget.player.setPlaybackSpeed(step),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _speed == 1.0
                ? null
                : () {
                    setState(() => _speed = 1.0);
                    widget.player.setPlaybackSpeed(1.0);
                  },
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('恢复默认'),
          ),
        ),
      ],
    );

    if (widget.inDialog) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: content,
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: content,
      ),
    );
  }
}

/// 倍速滑块 + 档位标签。
///
/// 档位在 [kMinPlaybackSpeed, kMaxPlaybackSpeed] 线性轨道上不均匀分布，
/// 标签按各档位的真实比例定位，保证标签中心始终落在滑块拇指正下方。
class PlaybackSpeedScale extends StatelessWidget {
  const PlaybackSpeedScale({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  static const _thumbRadius = 10.0;
  static const _overlayRadius = 18.0;

  /// 轨道两端各内缩 max(overlayRadius, thumbRadius)，见
  /// BaseSliderTrackShape.getPreferredRect。
  static const _trackInset = _overlayRadius;

  double _fraction(double step) =>
      (step - kMinPlaybackSpeed) / (kMaxPlaybackSpeed - kMinPlaybackSpeed);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: _thumbRadius,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: _overlayRadius,
            ),
            overlayColor: colorScheme.primary.withValues(alpha: 0.12),
            activeTrackColor: colorScheme.primary,
            inactiveTrackColor: colorScheme.surfaceContainerHighest,
            thumbColor: colorScheme.primary,
          ),
          child: Slider(
            value: value.clamp(kMinPlaybackSpeed, kMaxPlaybackSpeed),
            min: kMinPlaybackSpeed,
            max: kMaxPlaybackSpeed,
            onChanged: (raw) => onChanged(snapToPlaybackSpeed(raw)),
            onChangeEnd: onChangeEnd == null
                ? null
                : (raw) => onChangeEnd!(snapToPlaybackSpeed(raw)),
          ),
        ),
        // 档位标签：位置 = 轨道内缩 + 档位比例 × 轨道宽度，与拇指中心重合。
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth - 2 * _trackInset;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: _trackInset),
              child: SizedBox(
                height: 32,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final step in kPlaybackSpeedSteps)
                      Positioned(
                        left: _fraction(step) * trackWidth,
                        top: 0,
                        bottom: 0,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: _SpeedStepLabel(
                            step: step,
                            active: snapToPlaybackSpeed(value) == step,
                            onTap: () {
                              onChanged(step);
                              onChangeEnd?.call(step);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SpeedStepLabel extends StatelessWidget {
  const _SpeedStepLabel({
    required this.step,
    required this.active,
    required this.onTap,
  });

  final double step;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          child: Text(
            formatPlaybackSpeed(step),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
