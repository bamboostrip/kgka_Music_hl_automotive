import 'package:flutter/material.dart';

class NowPlayingBadge extends StatefulWidget {
  const NowPlayingBadge({
    super.key,
    required this.active,
    required this.playing,
    required this.color,
    this.size = 18,
  });

  final bool active;
  final bool playing;
  final Color color;
  final double size;

  @override
  State<NowPlayingBadge> createState() => _NowPlayingBadgeState();
}

class _NowPlayingBadgeState extends State<NowPlayingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant NowPlayingBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.active && widget.playing) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else if (_controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return SizedBox.square(dimension: widget.size);
    }

    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _NowPlayingPainter(
              progress: widget.playing ? _controller.value : .42,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _NowPlayingPainter extends CustomPainter {
  const _NowPlayingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final barWidth = size.width / 5;
    final gap = barWidth / 2;
    final values = [
      .42 + .36 * progress,
      .72 - .28 * progress,
      .48 + .44 * (1 - (progress - .5).abs() * 2),
    ];

    for (var i = 0; i < values.length; i++) {
      final height = size.height * values[i].clamp(.28, .92);
      final left = i * (barWidth + gap) + gap / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - height, barWidth, height),
        Radius.circular(barWidth),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NowPlayingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
