import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../form_factor.dart';
import '../widgets/artwork.dart';
import '../widgets/mini_player.dart';
import 'playlist_detail_page.dart';

/// 推荐歌单二级卡片网格流页面。
class RecommendedPlaylistsPage extends StatefulWidget {
  const RecommendedPlaylistsPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    this.initialPlaylists,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final List<PlaylistSummary>? initialPlaylists;

  @override
  State<RecommendedPlaylistsPage> createState() =>
      _RecommendedPlaylistsPageState();
}

class _RecommendedPlaylistsPageState extends State<RecommendedPlaylistsPage> {
  final _scrollController = ScrollController();
  final List<PlaylistSummary> _playlists = [];
  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialPlaylists != null &&
        widget.initialPlaylists!.isNotEmpty) {
      _playlists.addAll(widget.initialPlaylists!);
      _page = 2;
    }
    _scrollController.addListener(_onScroll);
    if (_playlists.isEmpty) {
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
    setState(() {
      _isLoading = true;
    });
    try {
      final list = await widget.api.recommendedPlaylists(page: 1);
      if (!mounted) return;
      setState(() {
        _playlists
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
      final list = await widget.api.recommendedPlaylists(page: _page);
      if (!mounted) return;
      setState(() {
        if (list.isEmpty) {
          _hasMore = false;
        } else {
          final existingIds = _playlists.map((p) => p.id).toSet();
          final newItems =
              list.where((p) => !existingIds.contains(p.id)).toList();
          if (newItems.isEmpty) {
            _hasMore = false;
          } else {
            _playlists.addAll(newItems);
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

  void _openPlaylist(PlaylistSummary playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          playlist: playlist,
        ),
      ),
    );
  }

  String _formatPlayCount(int? count) {
    if (count == null || count <= 0) return '';
    if (count >= 100000000) {
      return '▶ ${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) {
      return '▶ ${(count / 10000).toStringAsFixed(1)}万';
    }
    return '▶ $count';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.sizeOf(context);
    // 车机横屏才走车机专属列数/字号，普通横屏与竖屏保持原样。
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
                      '推荐歌单',
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

                          if (_isLoading && _playlists.isEmpty) {
                            return const SizedBox(
                              height: 300,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          return ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context)
                                .copyWith(scrollbars: false),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _playlists.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: isCarMode ? 14 : 18,
                              crossAxisSpacing: isCarMode ? 12 : 14,
                              childAspectRatio: isCarMode ? 0.72 : 0.68,
                            ),
                            itemBuilder: (context, index) {
                              final playlist = _playlists[index];
                              final playCountText =
                                  _formatPlayCount(playlist.playCount);
                              final cardRadius = isDesktopFormFactor ? 8.0 : 12.0;
                              // 车机字号整体放大一级，保证驾驶距离可读。
                              final titleFontSize = isCarMode ? 15.5 : 13.5;
                              final subtitleFontSize = isCarMode ? 13.0 : 11.5;
                              final badgeFontSize = isCarMode ? 12.0 : 10.5;

                              return InkWell(
                                onTap: () => _openPlaylist(playlist),
                                borderRadius:
                                    BorderRadius.circular(cardRadius),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // 封面 + 播放量角标
                                    AspectRatio(
                                      aspectRatio: 1,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                cardRadius,
                                              ),
                                              border: Border.all(
                                                color: isDark
                                                    ? Colors.white
                                                        .withValues(alpha: .08)
                                                    : Colors.black
                                                        .withValues(alpha: .06),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(
                                                    alpha:
                                                        isDark ? 0.16 : 0.05,
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
                                                url: playlist.coverUrl,
                                                size: double.infinity,
                                                borderRadius: cardRadius,
                                              ),
                                            ),
                                          ),
                                          if (playCountText.isNotEmpty)
                                            Positioned(
                                              right: 6,
                                              bottom: 6,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  borderRadius:
                                                      BorderRadius.circular(99),
                                                ),
                                                child: Text(
                                                  playCountText,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: badgeFontSize,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      playlist.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: titleFontSize,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      playlist.subtitle ??
                                          playlist.creatorName ??
                                          '精选优质歌单',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: subtitleFontSize,
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
                          : (!_hasMore && _playlists.isNotEmpty
                              ? Text(
                                  '没有更多歌单了',
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

                // 底部防 MiniPlayer 遮挡留白
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
