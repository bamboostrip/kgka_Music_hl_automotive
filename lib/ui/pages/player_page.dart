import 'dart:async';
import 'dart:math' as math;
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
  var _lyricFocusRequest = 0;

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
                        onPageChanged: (value) {
                          setState(() {
                            _page = value;
                            if (value == 1) {
                              _lyricFocusRequest++;
                            }
                          });
                        },
                        children: [
                          _PosterPlayerPage(player: widget.player, song: song),
                          _LyricPlayerPage(
                            player: widget.player,
                            song: song,
                            focusRequest: _lyricFocusRequest,
                          ),
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
          const SizedBox(width: 4),
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
              _PosterLyricPreview(player: player),
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

int _activeLyricIndexFor(List<LyricLine> lyrics, Duration position) {
  if (lyrics.isEmpty) {
    return -1;
  }
  var index = 0;
  for (var i = 0; i < lyrics.length; i++) {
    if (position >= lyrics[i].time) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}

class _PosterLyricPreview extends StatefulWidget {
  const _PosterLyricPreview({required this.player});

  final PlayerController player;

  @override
  State<_PosterLyricPreview> createState() => _PosterLyricPreviewState();
}

class _PosterLyricPreviewState extends State<_PosterLyricPreview> {
  late final Ticker _ticker;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _position = widget.player.smoothPosition;
    _ticker = Ticker(_onTick);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _PosterLyricPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.player.isScrubbing) {
      _position = widget.player.smoothPosition;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final shouldTick =
        widget.player.isPlaying &&
        widget.player.lyrics.isNotEmpty &&
        !widget.player.isScrubbing;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || widget.player.isScrubbing) {
      return;
    }
    setState(() => _position = widget.player.smoothPosition);
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.player.lyrics;
    if (lyrics.isEmpty) {
      return SizedBox(
        height: 104,
        child: Center(
          child: Text(
            widget.player.isPreparing ? '歌词加载中...' : '暂无歌词',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white.withValues(alpha: .78),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    final index = _activeLyricIndexFor(lyrics, _position);
    final current = lyrics[index];
    final next = index + 1 < lyrics.length ? lyrics[index + 1] : null;
    final currentStyle = Theme.of(context).textTheme.titleLarge!.copyWith(
      color: Colors.white,
      fontSize: 23,
      height: 1.22,
      fontWeight: FontWeight.w900,
    );
    final nextStyle = Theme.of(context).textTheme.titleMedium!.copyWith(
      color: Colors.white.withValues(alpha: .46),
      height: 1.18,
      fontWeight: FontWeight.w700,
    );

    return SizedBox(
      height: 96,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: Column(
          key: ValueKey(current.time.inMilliseconds),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 36,
              child: _MarqueeSingleLine(
                textKey: current.time.inMilliseconds,
                child: _LyricText(
                  line: current,
                  active: true,
                  position: _position,
                  styleOverride: currentStyle,
                  textAlign: TextAlign.center,
                  singleLine: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 25,
              child: _MarqueeSingleLine(
                textKey: next?.time.inMilliseconds ?? -1,
                child: Text(
                  next?.text ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: nextStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarqueeSingleLine extends StatefulWidget {
  const _MarqueeSingleLine({required this.child, required this.textKey});

  final Widget child;
  final Object textKey;

  @override
  State<_MarqueeSingleLine> createState() => _MarqueeSingleLineState();
}

class _MarqueeSingleLineState extends State<_MarqueeSingleLine>
    with SingleTickerProviderStateMixin {
  final _viewportKey = GlobalKey();
  final _contentKey = GlobalKey();
  late final AnimationController _controller;
  double _overflow = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _MarqueeSingleLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textKey != widget.textKey) {
      _controller
        ..stop()
        ..reset();
      _overflow = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) {
      return;
    }
    final viewport = _viewportKey.currentContext?.size?.width ?? 0;
    final content = _contentKey.currentContext?.size?.width ?? 0;
    final overflow = math.max(0.0, content - viewport);
    if ((overflow - _overflow).abs() < 1) {
      return;
    }
    setState(() => _overflow = overflow);
    if (overflow > 0) {
      _controller
        ..duration = Duration(milliseconds: (overflow * 42).round() + 2600)
        ..repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          key: _viewportKey,
          child: SizedBox(
            width: constraints.maxWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = _overflow <= 0
                    ? 0.0
                    : -_overflow * _controller.value;
                return Align(
                  alignment: _overflow <= 0
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  ),
                );
              },
              child: OverflowBox(
                minWidth: 0,
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: RepaintBoundary(key: _contentKey, child: widget.child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LyricPlayerPage extends StatefulWidget {
  const _LyricPlayerPage({
    required this.player,
    required this.song,
    required this.focusRequest,
  });

  final PlayerController player;
  final Song song;
  final int focusRequest;

  @override
  State<_LyricPlayerPage> createState() => _LyricPlayerPageState();
}

class _LyricPlayerPageState extends State<_LyricPlayerPage> {
  var _showTranslation = true;

  @override
  Widget build(BuildContext context) {
    final hasTranslation = widget.player.lyrics.any(
      (line) => line.translation != null && line.translation!.isNotEmpty,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Stack(
        children: [
          _LyricViewport(
            player: widget.player,
            lyrics: widget.player.lyrics,
            activeIndex: widget.player.activeLyricIndex,
            seekRevision: widget.player.seekRevision,
            isPreparing: widget.player.isPreparing,
            showTranslation: _showTranslation,
            focusRequest: widget.focusRequest,
          ),
          if (hasTranslation)
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
    required this.seekRevision,
    required this.isPreparing,
    required this.showTranslation,
    required this.focusRequest,
  });

  final PlayerController player;
  final List<LyricLine> lyrics;
  final int activeIndex;
  final int seekRevision;
  final bool isPreparing;
  final bool showTranslation;
  final int focusRequest;

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
  double _scrollStretch = 0;

  @override
  void initState() {
    super.initState();
    _syncLineKeys();
    _framePosition = widget.player.smoothPosition;
    _frameActiveIndex = _activeIndexFor(_framePosition);
    _ticker = Ticker(_onTick);
    _syncTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) => _forceLockToActive());
  }

  @override
  void didUpdateWidget(covariant _LyricViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLineKeys();
    if (!widget.player.isScrubbing) {
      _framePosition = widget.player.smoothPosition;
    }
    final nextIndex = _activeIndexFor(_framePosition);
    final lyricsChanged = oldWidget.lyrics != widget.lyrics;
    final focusRequested = oldWidget.focusRequest != widget.focusRequest;
    final seekChanged = oldWidget.seekRevision != widget.seekRevision;
    if (lyricsChanged || focusRequested || seekChanged) {
      _frameActiveIndex = nextIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) => _forceLockToActive());
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
    final shouldTick =
        widget.player.isPlaying &&
        widget.lyrics.isNotEmpty &&
        !widget.player.isScrubbing;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || widget.player.isScrubbing) {
      return;
    }
    final position = widget.player.smoothPosition;
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
    return _activeLyricIndexFor(widget.lyrics, position);
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
      _jumpToEstimatedPosition();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
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

  void _jumpToEstimatedPosition() {
    if (!_controller.hasClients || _frameActiveIndex < 0) {
      return;
    }
    const topPadding = 180.0;
    const estimatedLineHeight = 80.0;
    final viewportHeight = _controller.position.viewportDimension;
    final maxScroll = _controller.position.maxScrollExtent;
    if (viewportHeight <= 0) {
      return;
    }
    final offset =
        topPadding +
        _frameActiveIndex * estimatedLineHeight -
        viewportHeight * 0.34;
    _controller.jumpTo(offset.clamp(0.0, maxScroll));
  }

  void _forceLockToActive() {
    if (!mounted) {
      return;
    }
    _resumeAutoScrollTimer?.cancel();
    _manualScrolling = false;
    _framePosition = widget.player.smoothPosition;
    _frameActiveIndex = _activeIndexFor(_framePosition);
    _jumpToEstimatedPosition();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    Timer(const Duration(milliseconds: 80), () {
      if (mounted) {
        _scrollToActive();
      }
    });
    Timer(const Duration(milliseconds: 220), () {
      if (mounted) {
        _scrollToActive();
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _applyStretch(notification.scrollDelta ?? 0);
      _pauseAutoScroll();
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _pauseAutoScroll();
    } else if (notification is ScrollEndNotification) {
      _settleStretch();
      _scheduleAutoScrollResume();
    }
    return false;
  }

  void _applyStretch(double delta) {
    final next = (delta * .9).clamp(-18.0, 18.0);
    if ((_scrollStretch - next).abs() < .4) {
      return;
    }
    setState(() => _scrollStretch = next);
  }

  void _settleStretch() {
    if (_scrollStretch == 0) {
      return;
    }
    setState(() => _scrollStretch = 0);
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
      child: ListView(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(0, 180, 0, 220),
        children: [
          for (var index = 0; index < lyrics.length; index++)
            Builder(
              builder: (context) {
                final active = index == _frameActiveIndex;
                final distance = index - _frameActiveIndex;
                final nearby = distance.abs() <= 1;
                final pull = !active
                    ? (_scrollStretch * (1 / (distance.abs() + 1))).clamp(
                        -10.0,
                        10.0,
                      )
                    : 0.0;
                final scale = active
                    ? 1.0
                    : (1 - (pull.abs() / 260)).clamp(.96, 1.0);
                final line = lyrics[index];
                return KeyedSubtree(
                  key: _lineKeys[index],
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: active ? 1 : (nearby ? .46 : .22),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pull),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedPull, child) {
                        return Transform.translate(
                          offset: Offset(0, animatedPull),
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        );
                      },
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
                  ),
                );
              },
            ),
        ],
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
    this.styleOverride,
    this.textAlign = TextAlign.start,
    this.singleLine = false,
  });

  final LyricLine line;
  final bool active;
  final Duration position;
  final TextStyle? styleOverride;
  final TextAlign textAlign;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final style =
        styleOverride ??
        Theme.of(context).textTheme.headlineMedium!.copyWith(
          color: Colors.white,
          fontSize: active ? 34 : 27,
          height: 1.24,
          fontWeight: active ? FontWeight.w900 : FontWeight.w800,
        );

    if (!active || line.words.isEmpty) {
      if (singleLine) {
        return Text(
          line.text,
          textAlign: textAlign,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: style,
        );
      }
      return AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        style: style,
        child: Text(
          line.text,
          textAlign: textAlign,
          maxLines: singleLine ? 1 : null,
          softWrap: !singleLine,
          overflow: singleLine ? TextOverflow.visible : TextOverflow.clip,
        ),
      );
    }

    if (singleLine) {
      final painter = _KaraokeLinePainter(
        line: line,
        position: position,
        style: style,
        baseColor: Colors.white.withValues(alpha: .34),
        activeColor: Colors.white,
        textDirection: Directionality.of(context),
        textAlign: textAlign,
        maxLines: 1,
        maxWidth: double.infinity,
      );
      return CustomPaint(
        size: Size(painter.width, painter.height),
        painter: painter,
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
          textAlign: textAlign,
          maxLines: singleLine ? 1 : null,
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
    required this.textAlign,
    required this.maxLines,
    required this.maxWidth,
  }) {
    _textPainter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: baseColor),
      ),
      textDirection: textDirection,
      textAlign: textAlign,
      maxLines: maxLines,
    )..layout(maxWidth: maxLines == 1 ? double.infinity : maxWidth);
  }

  final LyricLine line;
  final Duration position;
  final TextStyle style;
  final Color baseColor;
  final Color activeColor;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final int? maxLines;
  final double maxWidth;
  late final TextPainter _textPainter;

  double get width => _textPainter.width;

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
      textAlign: textAlign,
      maxLines: maxLines,
    )..layout(maxWidth: maxLines == 1 ? double.infinity : maxWidth);

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
    final value = player.smoothPosition.inMilliseconds
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
                player.previewSeek(Duration(milliseconds: value.round())),
            onChangeEnd: (value) =>
                player.seek(Duration(milliseconds: value.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                formatDuration(player.smoothPosition),
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
