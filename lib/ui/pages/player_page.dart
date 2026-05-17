import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../widgets/artwork.dart';
import '../widgets/song_action_sheets.dart';
import 'comment_page.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.player, required this.auth});

  final PlayerController player;
  final AuthController auth;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const _screenChannel = MethodChannel('kgka_music_hl/screen');

  @override
  void initState() {
    super.initState();
    unawaited(_setKeepScreenOn(true));
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    unawaited(_setKeepScreenOn(false));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    try {
      await _screenChannel.invokeMethod<void>('setKeepScreenOn', enabled);
    } on MissingPluginException {
      // Non-Android targets can ignore this page-level screen setting.
    } on PlatformException {
      // Keeping playback usable is more important than failing the page open.
    }
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

        return _PlayerBody(
          player: widget.player,
          auth: widget.auth,
          song: song,
          onClose: () => Navigator.of(context).pop(),
          onQueue: () => _showQueue(context),
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

class _PlayerBody extends StatefulWidget {
  const _PlayerBody({
    required this.player,
    required this.auth,
    required this.song,
    required this.onClose,
    required this.onQueue,
  });

  final PlayerController player;
  final AuthController auth;
  final Song song;
  final VoidCallback onClose;
  final VoidCallback onQueue;

  @override
  State<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<_PlayerBody> {
  final _pageController = PageController();
  var _page = 0;
  var _pageScrolling = false;
  var _lyricFocusRequest = 0;
  bool? _lastSystemUiLandscape;

  bool get _lyricPageActive => _page == 1 && !_pageScrolling;

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    _syncSystemUi(landscape);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _ArtworkBackground(song: widget.song),
            SafeArea(
              top: !landscape,
              bottom: !landscape,
              child: Column(
                children: [
                  if (!landscape)
                    _TopBar(
                      auth: widget.auth,
                      song: widget.song,
                      onClose: widget.onClose,
                    ),
                  Expanded(
                    child: landscape
                        ? _LandscapePlayerContent(
                            player: widget.player,
                            auth: widget.auth,
                            song: widget.song,
                            onClose: widget.onClose,
                            onQueue: widget.onQueue,
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: _handlePageScrollNotification,
                            child: PageView(
                              controller: _pageController,
                              onPageChanged: (value) =>
                                  _setPageState(page: value),
                              children: [
                                _PosterPlayerPage(
                                  key: const PageStorageKey(
                                    'poster-player-page',
                                  ),
                                  player: widget.player,
                                  song: widget.song,
                                  onQueue: widget.onQueue,
                                ),
                                _LyricPlayerPage(
                                  key: const PageStorageKey(
                                    'lyric-player-page',
                                  ),
                                  player: widget.player,
                                  song: widget.song,
                                  focusRequest: _lyricFocusRequest,
                                  isPageActive: _lyricPageActive,
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (!landscape) _PageDots(page: _page),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _syncSystemUi(bool landscape) {
    if (_lastSystemUiLandscape == landscape) {
      return;
    }
    _lastSystemUiLandscape = landscape;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      SystemChrome.setEnabledSystemUIMode(
        landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    });
  }

  bool _handlePageScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _setPageState(scrolling: true);
    } else if (notification is ScrollEndNotification) {
      final page = (_pageController.page ?? _page.toDouble()).round().clamp(
        0,
        1,
      );
      _setPageState(page: page, scrolling: false);
    }
    return false;
  }

  void _setPageState({int? page, bool? scrolling}) {
    final wasLyricActive = _lyricPageActive;
    final nextPage = page ?? _page;
    final nextScrolling = scrolling ?? _pageScrolling;

    if (nextPage == _page && nextScrolling == _pageScrolling) {
      return;
    }

    setState(() {
      _page = nextPage;
      _pageScrolling = nextScrolling;
      final nextLyricActive = _page == 1 && !_pageScrolling;
      if (!wasLyricActive && nextLyricActive) {
        _lyricFocusRequest++;
      }
    });
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

class _LandscapePlayerContent extends StatelessWidget {
  const _LandscapePlayerContent({
    required this.player,
    required this.auth,
    required this.song,
    required this.onClose,
    required this.onQueue,
  });

  final PlayerController player;
  final AuthController auth;
  final Song song;
  final VoidCallback onClose;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 350;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 24,
            compact ? 4 : 10,
            compact ? 16 : 30,
            compact ? 8 : 14,
          ),
          child: Column(
            children: [
              _LandscapeHeader(
                auth: auth,
                song: song,
                onClose: onClose,
                compact: compact,
              ),
              SizedBox(height: compact ? 2 : 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 9,
                      child: _LandscapeArtworkShowcase(
                        player: player,
                        song: song,
                        compact: compact,
                      ),
                    ),
                    SizedBox(width: compact ? 18 : 34),
                    Expanded(
                      flex: 12,
                      child: _LandscapeRightPanel(
                        player: player,
                        onQueue: onQueue,
                        compact: compact,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LandscapeHeader extends StatelessWidget {
  const _LandscapeHeader({
    required this.auth,
    required this.song,
    required this.onClose,
    required this.compact,
  });

  final AuthController auth;
  final Song song;
  final VoidCallback onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final liked = auth.isLiked(song);
        return SizedBox(
          height: compact ? 40 : 48,
          child: Row(
            children: [
              _LandscapeHeaderButton(
                tooltip: '返回',
                size: compact ? 38 : 44,
                iconSize: compact ? 30 : 34,
                onPressed: onClose,
                icon: Icons.keyboard_arrow_left_rounded,
              ),
              SizedBox(width: compact ? 10 : 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .92),
                        fontSize: compact ? 15 : 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!compact)
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: .56),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              _LandscapeHeaderButton(
                tooltip: liked ? '取消喜欢' : '喜欢',
                size: compact ? 38 : 44,
                iconSize: compact ? 22 : 24,
                onPressed: () => auth.toggleLike(song),
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              SizedBox(width: compact ? 6 : 8),
              _LandscapeHeaderButton(
                tooltip: '更多',
                size: compact ? 38 : 44,
                iconSize: compact ? 22 : 24,
                onPressed: () => _showMoreSheet(context),
                icon: Icons.more_horiz_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoreSheet(BuildContext context) {
    showSongActionSheet(
      context: context,
      song: song,
      actions: [
        SongSheetAction(
          icon: Icons.playlist_add_rounded,
          title: '添加到歌单',
          onTap: () =>
              showAddToPlaylistSheet(context: context, auth: auth, song: song),
        ),
      ],
    );
  }
}

class _LandscapeHeaderButton extends StatelessWidget {
  const _LandscapeHeaderButton({
    required this.tooltip,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final double size;
  final double iconSize;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox.square(
          dimension: size,
          child: IconButton(
            color: Colors.white,
            iconSize: iconSize,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: size, height: size),
            onPressed: onPressed,
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}

class _LandscapeArtworkShowcase extends StatefulWidget {
  const _LandscapeArtworkShowcase({
    required this.player,
    required this.song,
    required this.compact,
  });

  final PlayerController player;
  final Song song;
  final bool compact;

  @override
  State<_LandscapeArtworkShowcase> createState() =>
      _LandscapeArtworkShowcaseState();
}

class _LandscapeArtworkShowcaseState extends State<_LandscapeArtworkShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    );
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant _LandscapeArtworkShowcase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.hash != widget.song.hash) {
      _rotationController.value = 0;
    }
    _syncRotation();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _syncRotation() {
    if (widget.player.isPlaying) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else if (_rotationController.isAnimating) {
      _rotationController.stop(canceled: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.min(constraints.maxWidth, constraints.maxHeight);
        final discSize = (available * (widget.compact ? .84 : .9))
            .clamp(150.0, 330.0)
            .toDouble();
        final coverSize = discSize * (widget.compact ? .58 : .70);

        return Center(
          child: SizedBox.square(
            dimension: discSize,
            child: AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotationController.value * math.pi * 2,
                  child: child,
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: .88),
                          Colors.white.withValues(alpha: .58),
                          Colors.white.withValues(alpha: .22),
                        ],
                        stops: const [0, .62, 1],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .26),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                  for (final ratio in const [.36, .52, .68, .82])
                    SizedBox.square(
                      dimension: discSize * ratio,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .16),
                          ),
                        ),
                      ),
                    ),
                  ClipOval(
                    child: Artwork(
                      url: widget.song.coverUrl,
                      size: coverSize,
                      borderRadius: coverSize,
                    ),
                  ),
                  SizedBox.square(
                    dimension: discSize * .08,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .82),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LandscapeRightPanel extends StatelessWidget {
  const _LandscapeRightPanel({
    required this.player,
    required this.onQueue,
    required this.compact,
  });

  final PlayerController player;
  final VoidCallback onQueue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final veryTight = constraints.maxHeight < 250;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _LandscapeLyricPanel(
                player: player,
                compact: compact || veryTight,
              ),
            ),
            SizedBox(height: veryTight ? 2 : 6),
            _Progress(player: player, bright: true, compact: true),
            SizedBox(height: veryTight ? 0 : 4),
            _Controls(
              player: player,
              bright: true,
              onQueue: onQueue,
              compactOverride: true,
              denseOverride: veryTight,
            ),
          ],
        );
      },
    );
  }
}

class _LandscapeLyricPanel extends StatefulWidget {
  const _LandscapeLyricPanel({required this.player, required this.compact});

  final PlayerController player;
  final bool compact;

  @override
  State<_LandscapeLyricPanel> createState() => _LandscapeLyricPanelState();
}

class _LandscapeLyricPanelState extends State<_LandscapeLyricPanel> {
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
  void didUpdateWidget(covariant _LandscapeLyricPanel oldWidget) {
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
    final player = widget.player;
    final lyrics = widget.player.lyrics;
    if (lyrics.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          player.isPreparing ? '正在准备音乐...' : '暂无歌词',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white.withValues(alpha: .82),
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    final activeIndex = _activeLyricIndexFor(
      lyrics,
      _position,
    ).clamp(0, lyrics.length - 1);
    final offsets = widget.compact ? const [-1, 0, 1] : const [-2, -1, 0, 1, 2];

    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final offset in offsets)
                      if (activeIndex + offset >= 0 &&
                          activeIndex + offset < lyrics.length)
                        _LandscapeLyricLine(
                          line: lyrics[activeIndex + offset],
                          position: _position,
                          active: offset == 0,
                          compact: widget.compact,
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LandscapeLyricLine extends StatelessWidget {
  const _LandscapeLyricLine({
    required this.line,
    required this.position,
    required this.active,
    required this.compact,
  });

  final LyricLine line;
  final Duration position;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final activeStyle = Theme.of(context).textTheme.headlineMedium!.copyWith(
      color: Colors.white,
      fontSize: compact ? 26 : 34,
      height: 1.18,
      fontWeight: FontWeight.w900,
    );
    final inactiveStyle = Theme.of(context).textTheme.titleLarge!.copyWith(
      color: Colors.white.withValues(alpha: .34),
      fontSize: compact ? 18 : 24,
      height: 1.18,
      fontWeight: FontWeight.w800,
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 5 : 8),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: active ? 1 : .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            active
                ? _LyricText(
                    line: line,
                    active: true,
                    position: position,
                    styleOverride: activeStyle,
                  )
                : Text(
                    line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: inactiveStyle,
                  ),
            if (active &&
                !compact &&
                line.translation != null &&
                line.translation!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                line.translation!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .54),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.auth,
    required this.song,
    required this.onClose,
  });

  final AuthController auth;
  final Song song;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final liked = auth.isLiked(song);
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
                tooltip: liked ? '取消喜欢' : '喜欢',
                onPressed: () => auth.toggleLike(song),
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              const SizedBox(width: 8),
              _GlassIconButton(
                tooltip: '更多',
                onPressed: () => _showMoreSheet(context),
                icon: Icons.more_horiz_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoreSheet(BuildContext context) {
    showSongActionSheet(
      context: context,
      song: song,
      actions: [
        SongSheetAction(
          icon: Icons.playlist_add_rounded,
          title: '添加到歌单',
          onTap: () =>
              showAddToPlaylistSheet(context: context, auth: auth, song: song),
        ),
      ],
    );
  }
}

class _PosterPlayerPage extends StatefulWidget {
  const _PosterPlayerPage({
    super.key,
    required this.player,
    required this.song,
    required this.onQueue,
  });

  final PlayerController player;
  final Song song;
  final VoidCallback onQueue;

  @override
  State<_PosterPlayerPage> createState() => _PosterPlayerPageState();
}

class _PosterPlayerPageState extends State<_PosterPlayerPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final artworkMaxWidth = compact ? 250.0 : 330.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
          child: Column(
            children: [
              const Spacer(),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: artworkMaxWidth),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Artwork(
                    url: widget.song.coverUrl,
                    size: double.infinity,
                    borderRadius: 8,
                  ),
                ),
              ),
              SizedBox(height: compact ? 14 : 26),
              _PosterLyricPreview(player: widget.player),
              if (!compact) const SizedBox(height: 4),
              _CommentEntry(player: widget.player, song: widget.song),
              const Spacer(),
              _Progress(player: widget.player, bright: true),
              const SizedBox(height: 10),
              _Controls(
                player: widget.player,
                bright: true,
                onQueue: widget.onQueue,
              ),
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
    super.key,
    required this.player,
    required this.song,
    required this.focusRequest,
    required this.isPageActive,
  });

  final PlayerController player;
  final Song song;
  final int focusRequest;
  final bool isPageActive;

  @override
  State<_LyricPlayerPage> createState() => _LyricPlayerPageState();
}

class _LyricPlayerPageState extends State<_LyricPlayerPage>
    with AutomaticKeepAliveClientMixin {
  var _showTranslation = true;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
            isPageActive: widget.isPageActive,
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
    required this.isPageActive,
  });

  final PlayerController player;
  final List<LyricLine> lyrics;
  final int activeIndex;
  final int seekRevision;
  final bool isPreparing;
  final bool showTranslation;
  final int focusRequest;
  final bool isPageActive;

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
  bool _autoScrolling = false;
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
    final becameActive = !oldWidget.isPageActive && widget.isPageActive;
    if ((lyricsChanged || focusRequested || seekChanged || becameActive) &&
        widget.isPageActive) {
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
        widget.isPageActive &&
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
    if (!widget.isPageActive || _manualScrolling || _frameActiveIndex < 0) {
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
    _autoScrolling = true;
    Scrollable.ensureVisible(
      context,
      alignment: .34,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    ).whenComplete(() {
      if (mounted) {
        _autoScrolling = false;
      }
    });
  }

  void _jumpToEstimatedPosition() {
    if (!widget.isPageActive ||
        !_controller.hasClients ||
        _frameActiveIndex < 0) {
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
    if (!mounted || !widget.isPageActive) {
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
    if (_autoScrolling) {
      return false;
    }

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pauseAutoScroll();
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _applyStretch(notification.scrollDelta ?? 0);
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
  const _Progress({
    required this.player,
    this.bright = false,
    this.compact = false,
  });

  final PlayerController player;
  final bool bright;
  final bool compact;

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
            trackHeight: compact ? 3 : 5,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: compact ? 4 : 5,
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: compact ? 10 : 14,
            ),
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
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
          child: Row(
            children: [
              Text(
                formatDuration(player.smoothPosition),
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 12 : null,
                ),
              ),
              const Spacer(),
              Text(
                formatDuration(player.duration),
                style: TextStyle(
                  color: textColor,
                  fontSize: compact ? 12 : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.player,
    required this.onQueue,
    this.bright = false,
    this.compactOverride = false,
    this.denseOverride = false,
  });

  final PlayerController player;
  final VoidCallback onQueue;
  final bool bright;
  final bool compactOverride;
  final bool denseOverride;

  @override
  Widget build(BuildContext context) {
    final color = bright
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = compactOverride || constraints.maxWidth < 360;
        final dense = denseOverride;
        final edgeButtonSize = dense ? 34.0 : (compact ? 40.0 : 44.0);
        final edgeIconSize = dense ? 21.0 : (compact ? 24.0 : 27.0);
        final skipButtonSize = dense ? 42.0 : (compact ? 50.0 : 56.0);
        final skipIconSize = dense ? 33.0 : (compact ? 40.0 : 46.0);
        final playButtonSize = dense ? 58.0 : (compact ? 72.0 : 82.0);
        final playIconSize = dense ? 46.0 : (compact ? 56.0 : 64.0);
        final gap = dense ? 3.0 : (compact ? 5.0 : 9.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: edgeButtonSize,
              child: IconButton(
                tooltip: player.playbackModeLabel,
                color: color,
                iconSize: edgeIconSize,
                padding: EdgeInsets.zero,
                onPressed: () {
                  player.cyclePlaybackMode();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text('已切换到${player.playbackModeLabel}'),
                        duration: const Duration(milliseconds: 1100),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
                icon: Icon(_playbackModeIcon(player.playbackMode)),
              ),
            ),
            SizedBox(width: gap),
            SizedBox.square(
              dimension: skipButtonSize,
              child: IconButton(
                tooltip: '上一首',
                color: color,
                iconSize: skipIconSize,
                padding: EdgeInsets.zero,
                onPressed: player.previous,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
            ),
            SizedBox(width: gap),
            SizedBox.square(
              dimension: playButtonSize,
              child: IconButton(
                tooltip: player.isPlaying ? '暂停' : '播放',
                color: color,
                padding: EdgeInsets.zero,
                onPressed: player.isPreparing ? null : player.togglePlay,
                iconSize: playIconSize,
                icon: player.isPreparing
                    ? SizedBox.square(
                        dimension: compact ? 24 : 28,
                        child: const CircularProgressIndicator(
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
            SizedBox(width: gap),
            SizedBox.square(
              dimension: skipButtonSize,
              child: IconButton(
                tooltip: '下一首',
                color: color,
                iconSize: skipIconSize,
                padding: EdgeInsets.zero,
                onPressed: player.next,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ),
            SizedBox(width: gap),
            SizedBox.square(
              dimension: edgeButtonSize,
              child: IconButton(
                tooltip: '播放列表',
                color: color,
                iconSize: edgeIconSize,
                padding: EdgeInsets.zero,
                onPressed: onQueue,
                icon: const Icon(Icons.queue_music_rounded),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _playbackModeIcon(PlaybackMode mode) {
    return switch (mode) {
      PlaybackMode.playlistLoop => Icons.repeat_rounded,
      PlaybackMode.shuffle => Icons.shuffle_rounded,
      PlaybackMode.singleLoop => Icons.repeat_one_rounded,
    };
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

class _CommentEntry extends StatelessWidget {
  const _CommentEntry({required this.player, required this.song});

  final PlayerController player;
  final Song song;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final mixsongid = song.albumAudioId ?? song.id;
            if (mixsongid.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CommentPage(api: player.api, mixsongid: mixsongid),
              ),
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(
              Icons.comment_outlined,
              size: 20,
              color: Colors.white54,
            ),
          ),
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
