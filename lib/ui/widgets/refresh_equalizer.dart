import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 顶部刷新均衡器动画：对应 tab 正在刷新（下拉刷新、双击首页、桌面刷新按钮、
/// 后台静默刷新）时，在内容顶部居中展示一组跳动的竖条，让用户明确感知到
/// "正在刷新"；平时收起为零高度，不占位。
///
/// 极快的刷新（命中缓存/极速响应）从出现到消失可能不足百毫秒，用户根本
/// 感知不到刷新发生过，因此带 [minVisibleDuration] 最短展示时长：visible
/// 提前变 false 后竖条继续保持跳动，满足最短时长才收起。
class RefreshEqualizer extends StatefulWidget {
  const RefreshEqualizer({
    super.key,
    required this.visible,
    this.color,
    this.height = 26,
    this.minVisibleDuration = const Duration(milliseconds: 600),
  });

  /// 是否展示动画；切换时带高度展开/收起过渡。
  final bool visible;

  /// 竖条颜色，默认取主题主色（深浅模式自适应）。
  final Color? color;

  /// 展开时的整体高度。
  final double height;

  /// 最短展示时长：visible=false 请求收起时，若展示不足该时长则继续展示
  /// 到满足为止，保证刷新反馈可感知。
  final Duration minVisibleDuration;

  @override
  State<RefreshEqualizer> createState() => _RefreshEqualizerState();
}

class _RefreshEqualizerState extends State<RefreshEqualizer>
    with SingleTickerProviderStateMixin {
  static const _barCount = 5;

  late final AnimationController _controller;

  /// 实际展示态。visible=true 立即为真；visible=false 后进入收起保持期
  /// （[_holdingForHide]），最短展示时长满足后才真正收起。
  bool _shown = false;
  bool _holdingForHide = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.visible) {
      _shown = true;
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RefreshEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      if (_holdingForHide) {
        // 收起保持期内又来了新刷新：取消保持，继续跳动展示。
        _holdingForHide = false;
        _controller.repeat();
      } else if (!_shown) {
        _shown = true;
        _controller.repeat();
        setState(() {});
      }
    } else if (_shown) {
      // 刷新结束：不立即收起，用一段收尾动画占满最短展示时长后再收起。
      // （用控制器动画而非 Timer：测试环境 FakeAsync 下可随 pump 推进，
      // 不会遗留挂起定时器。）
      _holdingForHide = true;
      _controller
          .animateTo(
            1.0,
            duration: widget.minVisibleDuration,
            curve: Curves.linear,
          )
          .whenComplete(_collapse);
    }
  }

  /// 收起保持期结束，真正收起。
  void _collapse() {
    if (!mounted || !_shown || !_holdingForHide) return;
    _holdingForHide = false;
    _shown = false;
    _controller.stop();
    setState(() {});
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
      child: _shown
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
                            margin:
                                const EdgeInsets.symmetric(horizontal: 2.5),
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
