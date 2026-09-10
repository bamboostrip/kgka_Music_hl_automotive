import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../form_factor.dart';
import 'desktop_anchored_menu.dart';

Future<void> showSleepTimerSheet({
  required BuildContext context,
  required PlayerController player,
}) {
  if (isDesktopFormFactor) {
    // 桌面形态用居中小窗，替代全宽底部弹层（与倍速面板同一形态）。
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _SleepTimerSheet(player: player),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _SleepTimerSheet(player: player),
  );
}

/// PC 二级菜单：定时选项（播放栏「更多」菜单二级进入，不弹窗）。
///
/// 时长点击即设并关闭；「播完当前歌曲再停止」为开关项；
/// 已激活时提供「关闭定时」。
Future<void> showDesktopSleepTimerMenu({
  required BuildContext context,
  required Offset anchor,
  required PlayerController player,
}) {
  return showDesktopAnchoredMenu<void>(
    context: context,
    anchor: anchor,
    builder: (menuContext) {
      return _DesktopSleepTimerMenu(
        player: player,
        onClose: () => Navigator.of(menuContext).pop(),
      );
    },
  );
}

class _DesktopSleepTimerMenu extends StatefulWidget {
  const _DesktopSleepTimerMenu({required this.player, required this.onClose});

  final PlayerController player;
  final VoidCallback onClose;

  @override
  State<_DesktopSleepTimerMenu> createState() => _DesktopSleepTimerMenuState();
}

class _DesktopSleepTimerMenuState extends State<_DesktopSleepTimerMenu> {
  late bool _finishSong;

  @override
  void initState() {
    super.initState();
    _finishSong =
        widget.player.isSleepFinishCurrentSong ||
        widget.player.sleepFinishCurrentSongOption;
  }

  void _setTimer(Duration duration) {
    widget.onClose();
    if (_finishSong) {
      widget.player.setSleepTimerFinishSong(duration);
    } else {
      widget.player.setSleepTimer(duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final isActive = player.isSleepTimerActive || player.isSleepFinishCurrentSong;
    final remaining = formatSleepRemaining(player.sleepTimerRemaining);

    return DesktopPopupMenuPanel(
      title: isActive && remaining.isNotEmpty ? '定时 · $remaining' : '定时播放',
      width: 220,
      trailing: isActive
          ? TextButton(
              onPressed: () {
                widget.onClose();
                player.cancelSleepTimer();
              },
              child: const Text('关闭定时'),
            )
          : null,
      children: [
        DesktopPopupMenuItem(
          label: '播完当前歌曲再停止',
          subtitle: _finishSong ? '开' : '关',
          selected: _finishSong,
          onTap: () {
            setState(() => _finishSong = !_finishSong);
            player.updateSleepTimerOption(_finishSong);
          },
        ),
        DesktopPopupMenuItem(
          label: '15 分钟',
          onTap: () => _setTimer(const Duration(minutes: 15)),
        ),
        DesktopPopupMenuItem(
          label: '30 分钟',
          onTap: () => _setTimer(const Duration(minutes: 30)),
        ),
        DesktopPopupMenuItem(
          label: '45 分钟',
          onTap: () => _setTimer(const Duration(minutes: 45)),
        ),
        DesktopPopupMenuItem(
          label: '60 分钟',
          onTap: () => _setTimer(const Duration(minutes: 60)),
        ),
        DesktopPopupMenuItem(
          label: '90 分钟',
          onTap: () => _setTimer(const Duration(minutes: 90)),
        ),
      ],
    );
  }
}

class _SleepTimerSheet extends StatefulWidget {
  const _SleepTimerSheet({required this.player});

  final PlayerController player;

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  bool _finishSong = false;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onPlayerUpdate);
    _finishSong = widget.player.isSleepFinishCurrentSong || widget.player.sleepFinishCurrentSongOption;
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerUpdate);
    super.dispose();
  }

  void _onPlayerUpdate() {
    if (mounted) {
      setState(() {
        _finishSong = widget.player.isSleepFinishCurrentSong || widget.player.sleepFinishCurrentSongOption;
      });
    }
  }

  void _setTimer(Duration duration) {
    if (_finishSong) {
      widget.player.setSleepTimerFinishSong(duration);
    } else {
      widget.player.setSleepTimer(duration);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final player = widget.player;
    final isActive = player.isSleepTimerActive || player.isSleepFinishCurrentSong;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bedtime_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  '定时播放',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  TextButton(
                    onPressed: () {
                      player.cancelSleepTimer();
                      Navigator.of(context).pop();
                    },
                    child: const Text('关闭定时'),
                  ),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: 8),
              _ActiveTimerDisplay(player: player),
            ],
            const SizedBox(height: 16),
            // Finish song toggle
            Material(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                value: _finishSong,
                onChanged: (v) {
                  setState(() => _finishSong = v);
                  widget.player.updateSleepTimerOption(v);
                },
                title: const Text('播完当前歌曲再停止'),
                subtitle: const Text('定时结束后，等当前歌曲播放完毕再暂停'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Time presets
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TimerChip(
                  label: '15 分钟',
                  onTap: () => _setTimer(const Duration(minutes: 15)),
                ),
                _TimerChip(
                  label: '30 分钟',
                  onTap: () => _setTimer(const Duration(minutes: 30)),
                ),
                _TimerChip(
                  label: '45 分钟',
                  onTap: () => _setTimer(const Duration(minutes: 45)),
                ),
                _TimerChip(
                  label: '60 分钟',
                  onTap: () => _setTimer(const Duration(minutes: 60)),
                ),
                _TimerChip(
                  label: '90 分钟',
                  onTap: () => _setTimer(const Duration(minutes: 90)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTimerDisplay extends StatelessWidget {
  const _ActiveTimerDisplay({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remaining = player.sleepTimerRemaining;

    String text;
    if (player.isSleepFinishCurrentSong) {
      if (remaining != null && remaining > Duration.zero) {
        final m = remaining.inMinutes;
        final s = remaining.inSeconds.remainder(60);
        text = '播完歌曲再停止  ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      } else {
        text = '播完当前歌曲后停止';
      }
    } else if (remaining != null && remaining > Duration.zero) {
      final m = remaining.inMinutes;
      final s = remaining.inSeconds.remainder(60);
      text = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      text = '已关闭';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

String formatSleepRemaining(Duration? remaining) {
  if (remaining == null || remaining <= Duration.zero) return '';
  final minutes = remaining.inMinutes;
  final seconds = remaining.inSeconds.remainder(60);
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
