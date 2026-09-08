import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 顶部刷新均衡器动画：对应 tab 正在刷新（下拉刷新、双击首页、桌面刷新按钮、
/// 后台静默刷新）时，在内容顶部居中展示一组跳动的竖条，让用户明确感知到
/// “正在刷新”；平时收起为零高度，不占位。
class RefreshEqualizer extends StatefulWidget {
  const RefreshEqualizer({
    super.key,
    required this.visible,
    this.color,
    this.height = 26,
  });

  /// 是否展示动画；切换时带高度展开/收起过渡。
  final bool visible;

  /// 竖条颜色，默认取主题主色（深浅模式自适应）。
  final Color? color;

  /// 展开时的整体高度。
  final double height;

  @override
  State<RefreshEqualizer> createState() => _RefreshEqualizerState();
}

class _RefreshEqualizerState extends State<RefreshEqualizer>
    with SingleTickerProviderStateMixin {
  static const _barCount = 5;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.visible) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RefreshEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.visible && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: widget.visible
          ? Semantics(
              liveRegion: true,
              label: '正在刷新',
              child: SizedBox(
                height: widget.height,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(_barCount, (i) {
                          final phase =
                              _controller.value * 2 * math.pi + i * 0.9;
                          final t = (math.sin(phase) + 1) / 2; // 0..1
                          final barHeight =
                              6.0 + t * (widget.height - 10.0);
                          return Container(
                            key: ValueKey('refresh_bar_$i'),
                            width: 3,
                            height: barHeight,
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
