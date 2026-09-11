import 'package:flutter/material.dart';

/// Calculates marquee scroll offset for long lyrics.
///
/// When [textWidth] <= [availableWidth], returns `0.0`.
/// When [textWidth] > [availableWidth], max scroll is `textWidth - availableWidth + 32.0`,
/// and returned offset is `-maxScroll * progress.clamp(0.0, 1.0)`.
double calculateMarqueeOffset({
  required double textWidth,
  required double availableWidth,
  required double progress,
}) {
  return LyricsKaraokeLine.calculateMarqueeOffset(
    textWidth: textWidth,
    availableWidth: availableWidth,
    progress: progress,
  );
}

/// Custom clipper for progressive karaoke highlight coloring.
class ProgressClipper extends CustomClipper<Rect> {
  const ProgressClipper({
    required this.progress,
    required this.textWidth,
  });

  final double progress;
  final double textWidth;

  @override
  Rect getClip(Size size) {
    final clipWidth =
        (textWidth * progress.clamp(0.0, 1.0)).clamp(0.0, double.infinity);
    return Rect.fromLTWH(0, 0, clipWidth, size.height + 20.0);
  }

  @override
  bool shouldReclip(covariant ProgressClipper oldClipper) {
    return oldClipper.progress != progress || oldClipper.textWidth != textWidth;
  }
}

/// Alias for internal progress clipper.
typedef _ProgressClipper = ProgressClipper;

/// 逐字变色歌词行渲染器与长歌词跑马灯平滑滚动组件。
///
/// 采用双层叠放架构 (Base unplayed layer + Top played highlight layer) 与
/// [ProgressClipper] 实现逐字/平滑变色渲染；
/// 当单行文本宽度超出 [availableWidth] 时，自动开启平滑跑马灯位移。
class LyricsKaraokeLine extends StatelessWidget {
  const LyricsKaraokeLine({
    super.key,
    required this.text,
    required this.fontSize,
    required this.playedColor,
    required this.unplayedColor,
    required this.progress,
    required this.availableWidth,
    this.alignment = TextAlign.center,
    this.textOpacity = 1.0,
    this.fontWeight = FontWeight.bold,
  });

  final String text;
  final double fontSize;
  final Color playedColor;
  final Color unplayedColor;
  final double progress;
  final double availableWidth;
  final TextAlign alignment;
  final double textOpacity;
  final FontWeight fontWeight;

  /// 计算跑马灯平移量（负值向左平移）。
  static double calculateMarqueeOffset({
    required double textWidth,
    required double availableWidth,
    required double progress,
  }) {
    if (textWidth <= availableWidth) {
      return 0.0;
    }
    final maxScroll = textWidth - availableWidth + 32.0;
    final clampedProgress = progress.clamp(0.0, 1.0);
    return -maxScroll * clampedProgress;
  }

  @override
  Widget build(BuildContext context) {
    final safeOpacity = textOpacity.clamp(0.0, 1.0);

    final unplayedShadows = [
      Shadow(
        color: Colors.black.withValues(alpha: (0.75 * safeOpacity).clamp(0.0, 1.0)),
        blurRadius: 6,
        offset: const Offset(0, 1),
      ),
      Shadow(
        color: Colors.black.withValues(alpha: (0.45 * safeOpacity).clamp(0.0, 1.0)),
        blurRadius: 14,
      ),
    ];

    final playedShadows = [
      Shadow(
        color: Colors.black.withValues(alpha: (0.85 * safeOpacity).clamp(0.0, 1.0)),
        blurRadius: 6,
        offset: const Offset(0, 1),
      ),
      Shadow(
        color: playedColor.withValues(alpha: (0.40 * safeOpacity).clamp(0.0, 1.0)),
        blurRadius: 12,
      ),
    ];

    final textStyle = TextStyle(
      decoration: TextDecoration.none,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );

    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final textWidth = painter.width;

    final isOverflow = textWidth > availableWidth;

    final karaokeStack = Stack(
      fit: StackFit.loose,
      children: [
        // Base Layer (unplayed)
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: textStyle.copyWith(
            color: unplayedColor.withValues(alpha: safeOpacity),
            shadows: unplayedShadows,
          ),
        ),
        // Top Highlight Layer (played)
        ClipRect(
          clipper: _ProgressClipper(
            progress: progress.clamp(0.0, 1.0),
            textWidth: textWidth,
          ),
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: textStyle.copyWith(
              color: playedColor.withValues(alpha: safeOpacity),
              shadows: playedShadows,
            ),
          ),
        ),
      ],
    );

    if (isOverflow) {
      final scrollOffset = calculateMarqueeOffset(
        textWidth: textWidth,
        availableWidth: availableWidth,
        progress: progress,
      );

      return SizedBox(
        width: availableWidth,
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(scrollOffset, 0),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: karaokeStack,
            ),
          ),
        ),
      );
    } else {
      final Alignment childAlignment = switch (alignment) {
        TextAlign.left || TextAlign.start => Alignment.centerLeft,
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        TextAlign.center || TextAlign.justify => Alignment.center,
      };

      return SizedBox(
        width: availableWidth,
        child: Align(
          alignment: childAlignment,
          child: karaokeStack,
        ),
      );
    }
  }
}
