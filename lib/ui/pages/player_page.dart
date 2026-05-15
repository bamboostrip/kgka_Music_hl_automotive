import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../widgets/artwork.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.player});

  final PlayerController player;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _pageController = PageController();
  var _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final song = widget.player.currentSong;
        if (song == null) {
          return const Scaffold(body: SizedBox.shrink());
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              _ArtworkBackground(song: song),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      song: song,
                      onClose: () => Navigator.of(context).pop(),
                      onQueue: () => _showQueue(context),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (value) => setState(() => _page = value),
                        children: [
                          _PosterPlayerPage(player: widget.player, song: song),
                          _LyricPlayerPage(player: widget.player, song: song),
                        ],
                      ),
                    ),
                    _PageDots(page: _page),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return AnimatedBuilder(
          animation: widget.player,
          builder: (context, _) {
            return ListView.builder(
              itemCount: widget.player.queue.length,
              itemBuilder: (context, index) {
                final song = widget.player.queue[index];
                final active = widget.player.currentSong?.hash == song.hash;
                return ListTile(
                  selected: active,
                  leading: Artwork(url: song.coverUrl, size: 44),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.player.playSong(song, queue: widget.player.queue);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ArtworkBackground extends StatelessWidget {
  const _ArtworkBackground({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final coverUrl = song.coverUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverUrl != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
            child: Transform.scale(
              scale: 1.18,
              child: Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _FallbackBackground(),
              ),
            ),
          )
        else
          const _FallbackBackground(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .32),
                Colors.black.withValues(alpha: .56),
                Colors.black.withValues(alpha: .82),
              ],
            ),
          ),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: .12)),
      ],
    );
  }
}

class _FallbackBackground extends StatelessWidget {
  const _FallbackBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF153D35), Color(0xFF061219), Color(0xFF2C1320)],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.song,
    required this.onClose,
    required this.onQueue,
  });

  final Song song;
  final VoidCallback onClose;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            color: Colors.white,
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          Artwork(url: song.coverUrl, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .72),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _GlassIconButton(
            tooltip: '收藏',
            onPressed: () {},
            icon: Icons.star_rounded,
          ),
          const SizedBox(width: 8),
          _GlassIconButton(
            tooltip: '队列',
            onPressed: onQueue,
            icon: Icons.more_horiz_rounded,
          ),
        ],
      ),
    );
  }
}

class _PosterPlayerPage extends StatelessWidget {
  const _PosterPlayerPage({required this.player, required this.song});

  final PlayerController player;
  final Song song;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
          child: Column(
            children: [
              const Spacer(),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 250 : 330),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Artwork(
                    url: song.coverUrl,
                    size: double.infinity,
                    borderRadius: 8,
                  ),
                ),
              ),
              SizedBox(height: compact ? 18 : 30),
              Text(
                song.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                song.artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .72),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _Progress(player: player, bright: true),
              const SizedBox(height: 10),
              _Controls(player: player, bright: true),
            ],
          ),
        );
      },
    );
  }
}

class _LyricPlayerPage extends StatefulWidget {
  const _LyricPlayerPage({required this.player, required this.song});

  final PlayerController player;
  final Song song;

  @override
  State<_LyricPlayerPage> createState() => _LyricPlayerPageState();
}

class _LyricPlayerPageState extends State<_LyricPlayerPage> {
  var _showTranslation = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Stack(
        children: [
          _LyricViewport(
            player: widget.player,
            lyrics: widget.player.lyrics,
            activeIndex: widget.player.activeLyricIndex,
            isPreparing: widget.player.isPreparing,
            showTranslation: _showTranslation,
          ),
          Positioned(
            right: 0,
            bottom: 16,
            child: _GlassIconButton(
              tooltip: _showTranslation ? '关闭翻译' : '显示翻译',
              onPressed: () {
                setState(() => _showTranslation = !_showTranslation);
              },
              icon: _showTranslation
                  ? Icons.translate_rounded
                  : Icons.translate_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricViewport extends StatefulWidget {
  const _LyricViewport({
    required this.player,
    required this.lyrics,
    required this.activeIndex,
    required this.isPreparing,
    required this.showTranslation,
  });

  final PlayerController player;
  final List<LyricLine> lyrics;
  final int activeIndex;
  final bool isPreparing;
  final bool showTranslation;

  @override
  State<_LyricViewport> createState() => _LyricViewportState();
}

class _LyricViewportState extends State<_LyricViewport> {
  final _controller = ScrollController();
  late final Ticker _ticker;
  var _lineKeys = <GlobalKey>[];
  Timer? _resumeAutoScrollTimer;
  Duration _framePosition = Duration.zero;
  int _frameActiveIndex = -1;
  bool _manualScrolling = false;

  @override
  void initState() {
    super.initState();
    _syncLineKeys();
    _framePosition = widget.player.position;
    _frameActiveIndex = widget.activeIndex;
    _ticker = Ticker(_onTick);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _LyricViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLineKeys();
    _framePosition = widget.player.position;
    final nextIndex = _activeIndexFor(_framePosition);
    if (nextIndex != _frameActiveIndex ||
        widget.activeIndex != oldWidget.activeIndex) {
      _frameActiveIndex = nextIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _resumeAutoScrollTimer?.cancel();
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncLineKeys() {
    if (_lineKeys.length == widget.lyrics.length) {
      return;
    }
    _lineKeys = List.generate(widget.lyrics.length, (_) => GlobalKey());
  }

  void _syncTicker() {
    final shouldTick = widget.player.isPlaying && widget.lyrics.isNotEmpty;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) {
      return;
    }
    final position = widget.player.audioPlayer.position;
    final activeIndex = _activeIndexFor(position);
    final shouldScroll = activeIndex != _frameActiveIndex;
    setState(() {
      _framePosition = position;
      _frameActiveIndex = activeIndex;
    });
    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  int _activeIndexFor(Duration position) {
    if (widget.lyrics.isEmpty) {
      return -1;
    }
    var index = 0;
    for (var i = 0; i < widget.lyrics.length; i++) {
      if (position >= widget.lyrics[i].time) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _scrollToActive() {
    if (_manualScrolling || _frameActiveIndex < 0) {
      return;
    }
    if (_frameActiveIndex >= _lineKeys.length) {
      return;
    }
    final context = _lineKeys[_frameActiveIndex].currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: .34,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _pauseAutoScroll();
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _pauseAutoScroll();
    } else if (notification is ScrollEndNotification) {
      _scheduleAutoScrollResume();
    }
    return false;
  }

  void _pauseAutoScroll() {
    _manualScrolling = true;
    _scheduleAutoScrollResume();
  }

  void _scheduleAutoScrollResume() {
    _resumeAutoScrollTimer?.cancel();
    _resumeAutoScrollTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      _manualScrolling = false;
      _scrollToActive();
    });
  }

  Widget _buildLyricList(List<LyricLine> lyrics) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(0, 180, 0, 220),
        itemCount: lyrics.length,
        itemBuilder: (context, index) {
          final active = index == _frameActiveIndex;
          final nearby = (index - _frameActiveIndex).abs() <= 1;
          final line = lyrics[index];
          return KeyedSubtree(
            key: _lineKeys[index],
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: active ? 1 : (nearby ? .46 : .22),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LyricText(
                      line: line,
                      active: active,
                      position: _framePosition,
                    ),
                    if (widget.showTranslation &&
                        line.translation != null &&
                        line.translation!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        line.translation!,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white.withValues(
                                alpha: active ? .62 : .38,
                              ),
                              height: 1.28,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    if (lyrics.isEmpty) {
      return Center(
        child: Text(
          widget.isPreparing ? '正在准备音乐...' : '暂无歌词',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, .14, .86, 1],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: _buildLyricList(lyrics),
    );
  }
}

class _LyricText extends StatelessWidget {
  const _LyricText({
    required this.line,
    required this.active,
    required this.position,
  });

  final LyricLine line;
  final bool active;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineMedium!.copyWith(
      color: Colors.white,
      fontSize: active ? 34 : 27,
      height: 1.24,
      fontWeight: active ? FontWeight.w900 : FontWeight.w800,
    );

    if (!active || line.words.isEmpty) {
      return AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        style: style,
        child: Text(line.text),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = _KaraokeLinePainter(
          line: line,
          position: position,
          style: style,
          baseColor: Colors.white.withValues(alpha: .34),
          activeColor: Colors.white,
          textDirection: Directionality.of(context),
          maxWidth: constraints.maxWidth,
        );

        return CustomPaint(
          size: Size(constraints.maxWidth, painter.height),
          painter: painter,
        );
      },
    );
  }
}

class _KaraokeLinePainter extends CustomPainter {
  _KaraokeLinePainter({
    required this.line,
    required this.position,
    required this.style,
    required this.baseColor,
    required this.activeColor,
    required this.textDirection,
    required this.maxWidth,
  }) {
    _textPainter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: baseColor),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: maxWidth);
  }

  final LyricLine line;
  final Duration position;
  final TextStyle style;
  final Color baseColor;
  final Color activeColor;
  final TextDirection textDirection;
  final double maxWidth;
  late final TextPainter _textPainter;

  double get height => _textPainter.height;

  @override
  void paint(Canvas canvas, Size size) {
    _textPainter.paint(canvas, Offset.zero);

    var start = 0;
    for (final word in line.words) {
      final end = start + word.text.length;
      final progress = _wordProgress(word);
      if (progress > 0) {
        _paintWordProgress(canvas, start, end, progress);
      }
      start = end;
    }
  }

  double _wordProgress(LyricWord word) {
    if (position < word.time) {
      return 0;
    }
    final durationMs = word.duration.inMilliseconds;
    if (durationMs <= 0) {
      return 1;
    }
    final elapsed = position.inMilliseconds - word.time.inMilliseconds;
    return (elapsed / durationMs).clamp(0, 1).toDouble();
  }

  void _paintWordProgress(Canvas canvas, int start, int end, double progress) {
    final selection = TextSelection(baseOffset: start, extentOffset: end);
    final boxes = _textPainter.getBoxesForSelection(selection);
    if (boxes.isEmpty) {
      return;
    }

    final highlightPainter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: activeColor),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: maxWidth);

    for (final box in boxes) {
      final rect = box.toRect();
      final width = rect.width * progress.clamp(0, 1);
      if (width <= 0) {
        continue;
      }

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(rect.left, rect.top, width, rect.height));
      highlightPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _KaraokeLinePainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.line != line ||
        oldDelegate.style != style ||
        oldDelegate.maxWidth != maxWidth;
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.player, this.bright = false});

  final PlayerController player;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    final max = player.duration.inMilliseconds <= 0
        ? 1.0
        : player.duration.inMilliseconds.toDouble();
    final value = player.position.inMilliseconds
        .clamp(0, max.toInt())
        .toDouble();
    final textColor = bright
        ? Colors.white.withValues(alpha: .64)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: bright
                ? Colors.white.withValues(alpha: .86)
                : Theme.of(context).colorScheme.primary,
            inactiveTrackColor: bright
                ? Colors.white.withValues(alpha: .25)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: (value) =>
                player.seek(Duration(milliseconds: value.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                formatDuration(player.position),
                style: TextStyle(color: textColor),
              ),
              const Spacer(),
              Text(
                formatDuration(player.duration),
                style: TextStyle(color: textColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player, this.bright = false});

  final PlayerController player;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    final color = bright
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '上一首',
          color: color,
          iconSize: 42,
          onPressed: player.previous,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 24),
        SizedBox.square(
          dimension: 76,
          child: IconButton(
            tooltip: player.isPlaying ? '暂停' : '播放',
            color: color,
            onPressed: player.isPreparing ? null : player.togglePlay,
            iconSize: 58,
            icon: player.isPreparing
                ? const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    player.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
          ),
        ),
        const SizedBox(width: 24),
        IconButton(
          tooltip: '下一首',
          color: color,
          iconSize: 42,
          onPressed: player.next,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .14),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          color: Colors.white,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(2, (index) {
          final active = index == page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: active ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: active ? .86 : .32),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }
}
