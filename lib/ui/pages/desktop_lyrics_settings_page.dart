import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../../services/desktop_lyrics_service.dart';
import '../desktop/lyrics_karaoke_line.dart';
import '../form_factor.dart';

class DesktopLyricsSettingsPage extends StatefulWidget {
  const DesktopLyricsSettingsPage({super.key, required this.player});

  final PlayerController player;

  @override
  State<DesktopLyricsSettingsPage> createState() =>
      _DesktopLyricsSettingsPageState();
}

class _DesktopLyricsSettingsPageState
    extends State<DesktopLyricsSettingsPage> {
  late DesktopLyricsSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.player.desktopLyricsSettings;
    // 托盘「解锁桌面歌词」/子窗工具栏锁定按钮修改锁定状态后，设置页需跟随
    // 刷新（PlayerController 是 ChangeNotifier，updateDesktopLyricsSettings
    // 会 notifyListeners）。
    widget.player.addListener(_syncFromPlayer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.player.setDesktopLyricsPreviewVisible(true);
      }
    });
  }

  @override
  void dispose() {
    widget.player.removeListener(_syncFromPlayer);
    widget.player.setDesktopLyricsPreviewVisible(false);
    super.dispose();
  }

  void _syncFromPlayer() {
    final next = widget.player.desktopLyricsSettings;
    if (next == _settings) return;
    setState(() => _settings = next);
  }

  void _update(DesktopLyricsSettings Function(DesktopLyricsSettings s) fn) {
    setState(() => _settings = fn(_settings));
    widget.player.updateDesktopLyricsSettings(_settings);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('桌面歌词设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Appearance
          _SectionHeader(title: '外观'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              _SegmentTile<bool>(
                icon: Icons.table_rows_rounded,
                iconColor: colorScheme.primary,
                title: '行数',
                selected: _settings.singleLine,
                segments: const [
                  ButtonSegment(value: true, label: Text('单行显示')),
                  ButtonSegment(value: false, label: Text('双行显示')),
                ],
                onChanged: (v) => _update((s) => s.copyWith(singleLine: v)),
              ),
              _SettingsDivider(),
              _SegmentTile<String>(
                icon: Icons.format_align_center_rounded,
                iconColor: colorScheme.primary,
                title: '对齐方式',
                selected: _settings.alignment,
                segments: const [
                  ButtonSegment(value: 'left', label: Text('左对齐')),
                  ButtonSegment(value: 'center', label: Text('居中对齐')),
                  ButtonSegment(value: 'right', label: Text('右对齐')),
                ],
                onChanged: (v) => _update((s) => s.copyWith(alignment: v)),
              ),
              _SettingsDivider(),
              _SliderTile(
                icon: Icons.format_size_rounded,
                iconColor: colorScheme.primary,
                title: '字体大小',
                value: _settings.fontSize,
                min: 12,
                max: 48,
                label: '${_settings.fontSize.round()}sp',
                onChanged: (v) => _update((s) => s.copyWith(fontSize: v)),
              ),
              _SettingsDivider(),
              _SliderTile(
                icon: Icons.format_paint_rounded,
                iconColor: colorScheme.primary,
                title: '文字透明度',
                value: _settings.textOpacity,
                min: 0.2,
                max: 1.0,
                label: '${(_settings.textOpacity * 100).round()}%',
                onChanged: (v) => _update((s) => s.copyWith(textOpacity: v)),
              ),
              _SettingsDivider(),
              _SliderTile(
                icon: Icons.opacity_rounded,
                iconColor: colorScheme.primary,
                title: '背景透明度',
                value: _settings.opacity,
                min: 0.0,
                max: 1.0,
                label: '${(_settings.opacity * 100).round()}%',
                onChanged: (v) => _update((s) => s.copyWith(opacity: v)),
              ),
              _SettingsDivider(),
              _ColorPickerTile(
                title: '歌词颜色',
                currentColor: Color(_settings.unplayedTextColor),
                presets: const [
                  Colors.white,
                  Color(0xFFFFD700), // Gold
                  Color(0xFFFF69B4), // Pink
                  Color(0xFF00BFFF), // Sky blue
                  Color(0xFF00FF7F), // Spring green
                  Color(0xFFFF6347), // Tomato
                  Color(0xFF000000), // Black
                ],
                onChanged: (c) => _update(
                  (s) => s.copyWith(
                    unplayedTextColor: c.toARGB32(),
                    textColor: c.toARGB32(),
                  ),
                ),
              ),
              _SettingsDivider(),
              _ColorPickerTile(
                title: '高亮颜色',
                currentColor: Color(_settings.playedTextColor),
                presets: const [
                  Color(0xFFFFD700), // Gold
                  Color(0xFFFFEE58), // Yellow
                  Color(0xFFFF6347), // Coral
                  Color(0xFF00BFFF), // Sky Blue
                  Color(0xFF00FF7F), // Spring Green
                  Color(0xFFFFFFFF), // White
                ],
                onChanged: (c) => _update(
                  (s) => s.copyWith(playedTextColor: c.toARGB32()),
                ),
              ),
              _SettingsDivider(),
              _ColorPickerTile(
                title: '背景颜色',
                currentColor: Color(_settings.backgroundColor),
                presets: const [
                  Color(0xFF1A1A2E), // Default Dark Blue
                  Color(0xFF000000), // Black
                  Color(0xFF222222), // Dark Grey
                  Color(0xFF3B1E1E), // Dark Red/Brown
                  Color(0xFF1B3B1E), // Dark Green
                  Color(0xFF2A1E3B), // Dark Purple
                  Color(0xFF1E353B), // Dark Teal
                ],
                onChanged: (c) => _update((s) => s.copyWith(backgroundColor: c.toARGB32())),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Behavior
          _SectionHeader(title: '行为'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: [
              _SwitchTile(
                icon: Icons.lock_rounded,
                iconColor: colorScheme.primary,
                title: isDesktopFormFactor ? '锁定桌面歌词' : '锁定位置',
                subtitle: isDesktopFormFactor
                    ? '锁定后桌面歌词鼠标穿透，可在托盘或此处解锁'
                    : '锁定后无法拖动移动歌词悬浮窗，点击悬浮窗锁图标可解锁',
                value: _settings.locked,
                // PC：桌面歌词未显示时锁定无意义，置灰。
                // 移动端保持原行为：开关始终可点（不改移动端）。
                onChanged: !isDesktopFormFactor ||
                        widget.player.desktopLyricsEnabled
                    ? (v) => _update((s) => s.copyWith(locked: v))
                    : null,
              ),
              // PC：锁定语义 = QQ 音乐式全穿透，"触摸穿透"已被锁定吸收，
              // 不再提供独立开关（旧持久化字段仍兼容解析）。
              // 移动端（Android 悬浮窗）locked 与 passthrough 是两个独立
              // 原生行为，开关原样保留，不动移动端。
              if (!isDesktopFormFactor) ...[
                _SettingsDivider(),
                _SwitchTile(
                  icon: Icons.touch_app_rounded,
                  iconColor: colorScheme.primary,
                  title: '触摸穿透',
                  subtitle: '启用后点击事件会穿透到下层应用',
                  value: _settings.passthrough,
                  onChanged: (v) => _update((s) => s.copyWith(passthrough: v)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: '效果预览'),
          const SizedBox(height: 8),
          _LyricsPreviewCard(settings: _settings),
        ],
      ),
    );
  }
}

// --- Shared widgets ---

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 54,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ColorPickerTile extends StatelessWidget {
  const _ColorPickerTile({
    required this.title,
    required this.currentColor,
    required this.presets,
    required this.onChanged,
  });

  final String title;
  final Color currentColor;
  final List<Color> presets;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, size: 22),
              const SizedBox(width: 14),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final color in presets)
                GestureDetector(
                  key: Key('color_${title}_${color.toARGB32().toRadixString(16)}'),
                  onTap: () => onChanged(color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: currentColor.toARGB32() == color.toARGB32()
                            ? Theme.of(context).colorScheme.primary
                            : (color.toARGB32() == Colors.black.toARGB32()
                                ? Colors.white30
                                : Colors.transparent),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.toARGB32() == Colors.black.toARGB32()
                              ? Colors.white12
                              : color.withValues(alpha: .4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: currentColor.toARGB32() == color.toARGB32()
                        ? Icon(Icons.check_rounded,
                            color: color.toARGB32() == Colors.black.toARGB32()
                                ? Colors.white70
                                : Colors.black54,
                            size: 20)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentTile<T> extends StatelessWidget {
  const _SegmentTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.selected,
    required this.segments,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final T selected;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 14),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: segments,
              selected: {selected},
              onSelectionChanged: (newSet) {
                if (newSet.isNotEmpty) {
                  onChanged(newSet.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsPreviewCard extends StatelessWidget {
  const _LyricsPreviewCard({required this.settings});

  final DesktopLyricsSettings settings;

  @override
  Widget build(BuildContext context) {
    final playedColor = Color(settings.playedTextColor);
    final unplayedColor = Color(settings.unplayedTextColor);
    final textAlign = switch (settings.alignment) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final lineAlignment = switch (settings.alignment) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };

    return Container(
      height: 110,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: Color(settings.backgroundColor)
            .withValues(alpha: settings.opacity),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final Widget body;
            if (settings.singleLine) {
              body = Align(
                alignment: lineAlignment,
                child: LyricsKaraokeLine(
                  text: '时音 听我想听',
                  fontSize: settings.fontSize,
                  playedColor: playedColor,
                  unplayedColor: unplayedColor,
                  progress: 0.45,
                  availableWidth: availableWidth,
                  alignment: textAlign,
                  textOpacity: settings.textOpacity,
                  fontWeight: FontWeight.bold,
                ),
              );
            } else {
              final dualLineWidth = availableWidth - 40.0;
              final effectiveDualWidth =
                  dualLineWidth > 0 ? dualLineWidth : availableWidth;
              body = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: LyricsKaraokeLine(
                      text: '时音 听我想听',
                      fontSize: settings.fontSize * 0.85,
                      playedColor: playedColor,
                      unplayedColor: unplayedColor,
                      progress: 0.45,
                      availableWidth: effectiveDualWidth,
                      alignment: TextAlign.left,
                      textOpacity: settings.textOpacity,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: LyricsKaraokeLine(
                      text: '让音乐更自由',
                      fontSize: settings.fontSize * 0.75,
                      playedColor: playedColor,
                      unplayedColor: unplayedColor.withValues(alpha: 0.65),
                      progress: 0.0,
                      availableWidth: effectiveDualWidth,
                      alignment: TextAlign.right,
                      textOpacity: settings.textOpacity * 0.65,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              );
            }

            return FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: availableWidth,
                child: body,
              ),
            );
          },
        ),
      ),
    );
  }
}
