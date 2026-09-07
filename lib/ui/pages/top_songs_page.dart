import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../form_factor.dart';
import '../widgets/app_feedback.dart';
import '../widgets/artwork.dart';
import '../widgets/cover_play_overlay.dart';
import '../widgets/mini_player.dart';
import '../widgets/now_playing_badge.dart';
import '../player/song_tap_handler.dart';

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
  bool _loadFailed = false;
  String? _loadError;

  /// 加载代数：下拉刷新开启新代数后，在途的 _loadMore 响应整体作废，
  /// 避免旧分页数据混入刷新后的列表、页码错位导致整页内容被跳过。
  int _generation = 0;

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
    final generation = ++_generation;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
      _loadError = null;
    });
    try {
      final list = await widget.api.topSongs(page: 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(list);
        _page = 2;
        _hasMore = list.isNotEmpty;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // 已有内容时保留列表不闪错误页；只有彻底没数据才进入错误态。
        _loadFailed = _songs.isEmpty;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final generation = _generation;
    setState(() => _isLoadingMore = true);
    try {
      final list = await widget.api.topSongs(page: _page);
      if (!mounted) return;
      if (generation != _generation) {
        // 等待期间发生了下拉刷新：新列表由刷新流程负责，本响应丢弃。
        setState(() => _isLoadingMore = false);
        return;
      }
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
    // 点到当前正在播的歌：不重头播放（与首页行为一致）。
    if (openPlayerIfSameSong(
      context,
      player: widget.player,
      auth: widget.auth,
      song: song,
    )) {
      return;
    }
    widget.player.playSong(song, queue: List<Song>.of(_songs));
  }

  int _resolveCrossAxisCount(double gridWidth, bool isCarMode) {
    if (isCarMode) {
      if (gridWidth >= 1100) return 6;
      if (gridWidth >= 850) return 5;
      if (gridWidth >= 600) return 4;
      return 3;
    }
    if (gridWidth >= 900) return 4;
    if (gridWidth >= 600) return 3;
    return 2;
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
          // 列数取决于网格区宽度（视口减左右 16 padding），在视口层级解析后
          // 直接使用 SliverGrid 懒构建：旧实现 GridView(shrinkWrap) 塞在
          // SliverToBoxAdapter 里会一次性构建全部卡片，翻页后越来越卡。
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount =
                  _resolveCrossAxisCount(constraints.maxWidth - 32, isCarMode);

              return RefreshIndicator(
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

                    if (_isLoading && _songs.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_songs.isEmpty && _loadFailed)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppErrorView(
                          message: friendlyServiceErrorMessage(
                            _loadError ?? '加载失败',
                          ),
                          onRetry: _loadInitial,
                        ),
                      )
                    else if (_songs.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppEmptyState(
                          icon: Icons.music_note_rounded,
                          title: '暂时没有新歌',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          isCarMode ? 16 : 20,
                          16,
                          12,
                        ),
                        sliver: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: isCarMode ? 14 : 18,
                              crossAxisSpacing: isCarMode ? 12 : 14,
                              childAspectRatio: isCarMode ? 0.74 : 0.72,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildCard(
                                context,
                                song: _songs[index],
                                isCarMode: isCarMode,
                                isDark: isDark,
                                colorScheme: colorScheme,
                              ),
                              childCount: _songs.length,
                            ),
                          ),
                        ),
                      ),

                    // 加载更多进度条或已到底提示
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

                    // 底部防 MiniPlayer 遮挡留白：MiniPlayer 仅在非车机横屏
                    // 且正在播放时显示，其余场景退化为普通收尾间距。
                    SliverToBoxAdapter(
                      child: AnimatedBuilder(
                        animation: widget.player,
                        builder: (context, _) {
                          final miniPlayerVisible =
                              !isCarMode && widget.player.currentSong != null;
                          return Container(
                            color: bodyBg,
                            height: miniPlayerVisible ? 88 : 24,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
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

  Widget _buildCard(
    BuildContext context, {
    required Song song,
    required bool isCarMode,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    // 正在播放高亮随播放状态实时变化：只重建单张卡片。
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final active = song.hash.isNotEmpty &&
            widget.player.currentSong?.hash == song.hash;
        final isDesktop = isDesktopFormFactor;
        final cardRadius = isDesktop ? 8.0 : 12.0;
        final titleFontSize = isCarMode ? 15.5 : 13.5;
        final artistFontSize = isCarMode ? 13.0 : 11.5;

        return InkWell(
          onTap: () => _playSong(song),
          borderRadius: BorderRadius.circular(cardRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          borderRadius: BorderRadius.circular(cardRadius),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: .08)
                                : Colors.black.withValues(alpha: .06),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.16 : 0.05,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(cardRadius),
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
                                .withValues(alpha: .88),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: NowPlayingBadge(
                              active: active,
                              playing: widget.player.isPlaying,
                              color: colorScheme.primary,
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
                  color: active ? colorScheme.primary : colorScheme.onSurface,
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
    );
  }
}
