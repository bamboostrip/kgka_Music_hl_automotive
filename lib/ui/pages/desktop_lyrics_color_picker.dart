import 'package:flutter/material.dart';

/// 桌面歌词取色弹窗：预设色块 + 自定义 HSV 取色（二维饱和度/明度面板 +
/// 色相滑杆），参考 QQ 音乐桌面歌词的紧凑取色交互。
///
/// 预设色块的 Key 约定为 `color_<title>_<hex>`，与设置页测试共用。
/// 返回所选颜色；取消/点击遮罩关闭返回 null。
Future<Color?> showLyricsColorPicker(
  BuildContext context, {
  required String title,
  required Color initial,
  required List<Color> presets,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _LyricsColorPickerDialog(
      title: title,
      initial: initial,
      presets: presets,
    ),
  );
}

class _LyricsColorPickerDialog extends StatefulWidget {
  const _LyricsColorPickerDialog({
    required this.title,
    required this.initial,
    required this.presets,
  });

  final String title;
  final Color initial;
  final List<Color> presets;

  @override
  State<_LyricsColorPickerDialog> createState() =>
      _LyricsColorPickerDialogState();
}

class _LyricsColorPickerDialogState extends State<_LyricsColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  void _update(HSVColor next) => setState(() => _hsv = next);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _SVPanel(hsv: _hsv, onChanged: _update),
              const SizedBox(height: 12),
              _HueTrack(
                hue: _hsv.hue,
                onChanged: (h) => _update(_hsv.withHue(h)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in widget.presets)
                    _PresetSwatch(
                      key: Key(
                        'color_${widget.title}_'
                        '${preset.toARGB32().toRadixString(16)}',
                      ),
                      color: preset,
                      selected: preset.toARGB32() == color.toARGB32(),
                      onTap: () => _update(HSVColor.fromColor(preset)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(color),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 二维取色面板：横向为饱和度（白 → 纯色），纵向为明度（亮 → 黑）。
class _SVPanel extends StatelessWidget {
  const _SVPanel({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const _cursorSize = 18.0;
  // 面板高度固定：外层 Column 传入的高度约束无上界，不能读 maxHeight。
  static const _panelHeight = 140.0;

  void _pick(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final s = (local.dx / box.size.width).clamp(0.0, 1.0);
    final v = 1.0 - (local.dy / box.size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1.0, hsv.hue, 1.0, 1.0).toColor();
    // Builder 提供 GestureDetector 所在子树的真实 RenderBox 定位上下文。
    return Builder(
      builder: (gestureContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(gestureContext, d.globalPosition),
        onPanStart: (d) => _pick(gestureContext, d.globalPosition),
        onPanUpdate: (d) => _pick(gestureContext, d.globalPosition),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = _panelHeight;
            return Container(
              height: _panelHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.white, hueColor],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (hsv.saturation * width - _cursorSize / 2).clamp(
                        0.0,
                        width - _cursorSize,
                      ),
                      top: ((1.0 - hsv.value) * height - _cursorSize / 2).clamp(
                        0.0,
                        height - _cursorSize,
                      ),
                      child: Container(
                        width: _cursorSize,
                        height: _cursorSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 色相滑杆：彩虹横条 + 圆形拖块。
class _HueTrack extends StatelessWidget {
  const _HueTrack({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const _thumbSize = 16.0;
  static const _trackHeight = 12.0;

  void _pick(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final fraction = (local.dx / box.size.width).clamp(0.0, 1.0);
    onChanged(fraction * 360);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (gestureContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(gestureContext, d.globalPosition),
        onHorizontalDragStart: (d) => _pick(gestureContext, d.globalPosition),
        onHorizontalDragUpdate: (d) => _pick(gestureContext, d.globalPosition),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: _trackHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_trackHeight / 2),
                        gradient: LinearGradient(
                          colors: [
                            for (var i = 0; i <= 6; i++)
                              HSVColor.fromAHSV(
                                1.0,
                                i * 60.0,
                                1.0,
                                1.0,
                              ).toColor(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (hue / 360 * width - _thumbSize / 2).clamp(
                      0.0,
                      width - _thumbSize,
                    ),
                    top: (_trackHeight - _thumbSize) / 2,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 预设色块；Key 由外层按 `color_<title>_<hex>` 约定传入，供测试定位。
class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 15,
                color: color.toARGB32() == Colors.black.toARGB32()
                    ? Colors.white70
                    : Colors.black54,
              )
            : null,
      ),
    );
  }
}
