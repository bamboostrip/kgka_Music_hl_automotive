import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';

Future<double?> showPlaybackSpeedSheet({
  required BuildContext context,
  required PlayerController player,
}) {
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      return _PlaybackSpeedSheet(player: player);
    },
  );
}

class _PlaybackSpeedSheet extends StatefulWidget {
  const _PlaybackSpeedSheet({required this.player});

  final PlayerController player;

  @override
  State<_PlaybackSpeedSheet> createState() => _PlaybackSpeedSheetState();
}

class _PlaybackSpeedSheetState extends State<_PlaybackSpeedSheet> {
  static const _min = 0.5;
  static const _max = 3.0;
  static const _steps = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = widget.player.playbackSpeed;
  }

  String _formatSpeed(double value) {
    if (value == value.roundToDouble()) return '${value.round()}x';
    return '${value}x';
  }

  double _snapToNearest(double value) {
    var closest = _steps.first;
    var minDist = (value - closest).abs();
    for (final step in _steps.skip(1)) {
      final dist = (value - step).abs();
      if (dist < minDist) {
        minDist = dist;
        closest = step;
      }
    }
    // Only snap if very close (within 0.06), otherwise allow free sliding
    if (minDist < 0.06) return closest;
    // Round to 2 decimal places for clean display
    return (value * 100).roundToDouble() / 100;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '倍速播放',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '调整音乐播放速度',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            // Current speed display
            Center(
              child: Text(
                _formatSpeed(_speed),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: _speed == 1.0
                      ? colorScheme.onSurface
                      : colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.surfaceContainerHighest,
                thumbColor: colorScheme.primary,
              ),
              child: Slider(
                value: _speed.clamp(_min, _max),
                min: _min,
                max: _max,
                onChanged: (value) {
                  setState(() => _speed = _snapToNearest(value));
                },
                onChangeEnd: (value) {
                  final snapped = _snapToNearest(value);
                  widget.player.setPlaybackSpeed(snapped);
                },
              ),
            ),
            // Step labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0.5x', style: _stepLabelStyle(context, _speed == 0.5)),
                  Text('1x', style: _stepLabelStyle(context, _speed == 1.0)),
                  Text('2x', style: _stepLabelStyle(context, _speed == 2.0)),
                  Text('3x', style: _stepLabelStyle(context, _speed == 3.0)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Reset button
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
        ),
      ),
    );
  }

  TextStyle? _stepLabelStyle(BuildContext context, bool active) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme.of(context).textTheme.bodySmall?.copyWith(
      color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
    );
  }
}
