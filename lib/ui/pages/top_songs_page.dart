import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../form_factor.dart';
import '../widgets/artwork.dart';
import '../widgets/cover_play_overlay.dart';
import '../widgets/mini_player.dart';
import '../widgets/now_playing_badge.dart';

/// 新歌速递二级卡片网格流页面。
class TopSongsPage extends StatefulWidget {
  const TopSongsPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    this.initialSongs,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final List<Song>? initialSongs;

  @override
  State<TopSongsPage> createState() => _TopSongsPageState();
}

class _TopSongsPageState extends State<TopSongsPage> {
  final _scrollController = ScrollController();
  final List<Song> _songs = [];
  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialSongs != null && widget.initialSongs!.isNotEmpty) {
      _songs.addAll(widget.initialSongs!);
      _page = 2;
    }
    _scrollController.addListener(_onScroll);
    if (_songs.isEmpty) {
      _loadInitial();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final list = await widget.api.topSongs(page: 1);
      if (!mounted) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(list);
        _page = 2;
        _hasMore = list.isNotEmpty;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final list = await widget.api.topSongs(page: _page);
      if (!mounted) return;
      setState(() {
        if (list.isEmpty) {
          _hasMore = false;
        } else {
          final existingHashes = _songs.map((s) => s.hash).toSet();
          final newItems =
              list.where((s) => !existingHashes.contains(s.hash)).toList();
          if (newItems.isEmpty) {
            _hasMore = false;
          } else {
            _songs.addAll(newItems);
            _page++;
          }
        }
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _playSong(Song song) {
    widget.player.playSong(song, queue: List<Song>.of(_songs));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.sizeOf(context);
    final isCarMode = screenSize.width > screenSize.height &&
        ThemeController.instance.carModeEnabled;
    final bodyBg = isDark ? colorScheme.surface : const Color(0xFFF7F8FA);

    return Scaffold(
      backgroundColor: bodyBg,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadInitial,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 清新浅色头：顶部淡蓝渐变底部直接收进 bodyBg，
                // 与下方内容同底色、无圆角纸片接缝，滚动收起后仍是同一底色。
                SliverAppBar(
                  pinned: true,
                  expandedHeight: isCarMode ? 148 : 120,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: bodyBg,
                  leading: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: colorScheme.onSurface,
                      size: isCarMode ? 28 : 24,
                    ),
                    tooltip: '返回',
                    visualDensity: VisualDensity.compact,
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: true,
                    titlePadding: const EdgeInsets.only(bottom: 14),
                    title: Text(
                      '新歌速递',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: isCarMode ? 20 : 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isDark
                              ? [
                                  const Color(0xFF1B2E49),
                                  const Color(0xFF0D121E),
                                  bodyBg,
                                ]
                              : [
                                  const Color(0xFFD3E8FF),
                                  const Color(0xFFEDF4FF),
                                  bodyBg,
                                ],
                          stops: const [0, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                ),

                // 主体网格：与头图同底色直接相连，去掉圆角纸片，避免横向分割线。
                SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(color: bodyBg),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          16, isCarMode ? 16 : 20, 16, 12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final int crossAxisCount;
                          if (isCarMode) {
                            if (width >= 1100) {
                              crossAxisCount = 6;
                            } else if (width >= 850) {
                              crossAxisCount = 5;
                            } else if (width >= 600) {
                              crossAxisCount = 4;
                            } else {
                              crossAxisCount = 3;
                            }
                          } else if (width >= 900) {
                            crossAxisCount = 4;
                          } else if (width >= 600) {
                            crossAxisCount = 3;
                          } else {
                            crossAxisCount = 2;
                          }

                          if (_isLoading && _songs.isEmpty) {
                            return const SizedBox(
                              height: 300,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          return AnimatedBuilder(
                            animation: widget.player,
                            builder: (context, _) {
                              return ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(scrollbars: false),
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _songs.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: isCarMode ? 14 : 18,
                                  crossAxisSpacing: isCarMode ? 12 : 14,
                                  childAspectRatio: isCarMode ? 0.74 : 0.72,
                                ),
                                itemBuilder: (context, index) {
                                  final song = _songs[index];
                                  final active = song.hash.isNotEmpty &&
                                      widget.player.currentSong?.hash ==
                                          song.hash;
                                  final isDesktop = isDesktopFormFactor;
                                  final cardRadius = isDesktop ? 8.0 : 12.0;
                                  final titleFontSize =
                                      isCarMode ? 15.5 : 13.5;
                                  final artistFontSize =
                                      isCarMode ? 13.0 : 11.5;

                                  return InkWell(
                                    onTap: () => _playSong(song),
                                    borderRadius:
                                        BorderRadius.circular(cardRadius),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 正方形大封面 + 悬浮/正在播放反馈
                                        AspectRatio(
                                          aspectRatio: 1,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              CoverPlayOverlay(
                                                enabled: isDesktop,
                                                onPlay: () => _playSong(song),
                                                borderRadius: cardRadius,
                                                buttonSize: 36,
                                                iconSize: 22,
                                                buttonColor: Colors.black54,
                                                iconColor: Colors.white,
                                                cover: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      cardRadius,
                                                    ),
                                                    border: Border.all(
                                                      color: isDark
                                                          ? Colors.white
                                                              .withValues(
                                                                  alpha: .08)
                                                          : Colors.black
                                                              .withValues(
                                                                  alpha: .06),
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                          alpha: isDark
                                                              ? 0.16
                                                              : 0.05,
                                                        ),
                                                        blurRadius: 8,
                                                        offset:
                                                            const Offset(0, 3),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      cardRadius,
                                                    ),
                                                    child: Artwork(
                                                      url: song.coverUrl,
                                                      size: double.infinity,
                                                      borderRadius: cardRadius,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (active)
                                                Positioned(
                                                  right: 6,
                                                  bottom: 6,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .surface
                                                          .withValues(
                                                              alpha: .88),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              3),
                                                      child: NowPlayingBadge(
                                                        active: active,
                                                        playing: widget
                                                            .player.isPlaying,
                                                        color: colorScheme
                                                            .primary,
                                                        size: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: titleFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: active
                                                ? colorScheme.primary
                                                : colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          song.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: artistFontSize,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // 加载更多进度条
                SliverToBoxAdapter(
                  child: Container(
                    color: bodyBg,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: _isLoadingMore
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : (!_hasMore && _songs.isNotEmpty
                              ? Text(
                                  '没有更多新歌了',
                                  style: TextStyle(
                                    fontSize: isCarMode ? 13.5 : 12,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                )
                              : const SizedBox.shrink()),
                    ),
                  ),
                ),

                // 底部留白防 MiniPlayer 遮挡
                SliverToBoxAdapter(
                  child: Container(
                    color: bodyBg,
                    height: 88,
                  ),
                ),
              ],
            ),
          ),

          // 悬浮 MiniPlayer
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(player: widget.player, auth: widget.auth),
          ),
        ],
      ),
    );
  }
}
