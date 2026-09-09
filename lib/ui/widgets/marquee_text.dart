import 'package:flutter/material.dart';

/// An animatable that implements a ping-pong marquee translation cycle:
/// 1. Pause at offset 0 for [p1] of total duration.
/// 2. Smoothly scroll forward to -[overflow] between [p1] and [p2].
/// 3. Pause at -[overflow] between [p2] and [p3].
/// 4. Smoothly scroll back to 0 between [p3] and 1.0.
class _MarqueeAnimatable extends Animatable<double> {
  const _MarqueeAnimatable({
    required this.overflow,
    required this.p1,
    required this.p2,
    required this.p3,
    this.curve = Curves.linear,
  });

  final double overflow;
  final double p1;
  final double p2;
  final double p3;
  final Curve curve;

  @override
  double transform(double t) {
    if (t <= p1) return 0.0;
    if (t <= p2) {
      final progress = (t - p1) / (p2 - p1);
      return -overflow * curve.transform(progress.clamp(0.0, 1.0));
    }
    if (t <= p3) return -overflow;
    final progress = (t - p3) / (1.0 - p3);
    return -overflow * (1.0 - curve.transform(progress.clamp(0.0, 1.0)));
  }
}

/// A reusable marquee text widget that smoothly scrolls overflowing text
/// in a ping-pong manner with pauses at the start and end boundaries.
///
/// When the text fits within the available width, it renders static [Text.rich]
/// with zero animation overhead.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.textSpan,
    this.style,
    this.velocity = 30.0,
    this.pauseDuration = const Duration(seconds: 2),
    this.curve = Curves.linear,
  });

  /// Convenience factory constructor for plain text strings.
  factory MarqueeText.text(
    String text, {
    Key? key,
    TextStyle? style,
    double velocity = 30.0,
    Duration pauseDuration = const Duration(seconds: 2),
    Curve curve = Curves.linear,
  }) {
    return MarqueeText(
      key: key,
      textSpan: TextSpan(text: text),
      style: style,
      velocity: velocity,
      pauseDuration: pauseDuration,
      curve: curve,
    );
  }

  /// The text content to display, supporting rich styling.
  final InlineSpan textSpan;

  /// Optional text style merged with default text style.
  final TextStyle? style;

  /// Scroll speed in pixels per second.
  final double velocity;

  /// Duration to pause at the start and end boundaries.
  final Duration pauseDuration;

  /// Curve applied during the forward and backward scrolling phases.
  final Curve curve;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double>? _animation;

  double? _lastOverflow;
  Duration? _lastPauseDuration;
  double? _lastVelocity;
  Curve? _lastCurve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle =
        widget.style != null ? defaultStyle.merge(widget.style) : defaultStyle;

    final InlineSpan measuredSpan;
    if (widget.textSpan is TextSpan) {
      final span = widget.textSpan as TextSpan;
      measuredSpan = TextSpan(
        text: span.text,
        children: span.children,
        style: span.style != null
            ? effectiveStyle.merge(span.style)
            : effectiveStyle,
        recognizer: span.recognizer,
        semanticsLabel: span.semanticsLabel,
      );
    } else {
      measuredSpan = TextSpan(
        style: effectiveStyle,
        children: [widget.textSpan],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        final painter = TextPainter(
          text: measuredSpan,
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();

        final textWidth = painter.width.ceilToDouble();
        painter.dispose();

        final overflow = textWidth - availableWidth;

        // If text fits in available width (or width is unconstrained):
        // Render static Text.rich with 0 animation overhead.
        if (availableWidth.isInfinite || overflow <= 0) {
          if (_controller.isAnimating) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _controller.isAnimating) {
                _controller.stop();
                _controller.reset();
              }
            });
          }
          _lastOverflow = null;
          return Text.rich(
            widget.textSpan,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          );
        }

        // Text overflows available width: ping-pong smooth horizontal scroll.
        final velocity = widget.velocity > 0 ? widget.velocity : 30.0;
        final pauseDuration =
            widget.pauseDuration < Duration.zero
                ? Duration.zero
                : widget.pauseDuration;
        final moveDurationMs = (overflow / velocity * 1000).round();
        final moveDuration = Duration(
          milliseconds: moveDurationMs > 0 ? moveDurationMs : 1,
        );
        final totalDuration = (pauseDuration * 2) + (moveDuration * 2);

        // 触发条件只看"影响滚动几何/时序"的量。刻意不做 textSpan/style 的
        // 实例比较：调用方（播放栏）每次重建都会 new 一个 TextSpan，身份
        // 比较会让无关重建（音量调节、播放暂停、hover）把滚动打回起点；
        // 文本/样式变化必然反映到 overflow（宽度变化）或实时渲染子树，
        // 无需单独感知。
        final needsUpdate =
            _lastOverflow != overflow ||
            _lastPauseDuration != pauseDuration ||
            _lastVelocity != velocity ||
            _lastCurve != widget.curve ||
            _animation == null;

        if (needsUpdate) {
          _lastOverflow = overflow;
          _lastPauseDuration = pauseDuration;
          _lastVelocity = velocity;
          _lastCurve = widget.curve;

          _controller.duration = totalDuration;

          final pauseMs = pauseDuration.inMicroseconds.toDouble();
          final moveMs = moveDuration.inMicroseconds.toDouble();
          final totalMs = totalDuration.inMicroseconds.toDouble();

          final p1 = totalMs > 0 ? pauseMs / totalMs : 0.0;
          final p2 = totalMs > 0 ? (pauseMs + moveMs) / totalMs : 0.5;
          final p3 = totalMs > 0 ? (2 * pauseMs + moveMs) / totalMs : 0.5;

          _animation = _MarqueeAnimatable(
            overflow: overflow,
            p1: p1,
            p2: p2,
            p3: p3,
            curve: widget.curve,
          ).animate(_controller);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _controller.reset();
            _controller.repeat();
          });
        }

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: textWidth,
            maxWidth: textWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = _animation?.value ?? 0.0;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Text.rich(
                widget.textSpan,
                style: widget.style,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        );
      },
    );
  }
}
