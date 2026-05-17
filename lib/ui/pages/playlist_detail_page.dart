import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import '../widgets/now_playing_badge.dart';
import '../widgets/song_action_sheets.dart';

enum _PlaylistAction { collect, deleteOrUncollect }

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.playlist,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final PlaylistSummary playlist;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  static const _pageSize = 50;

  final _scrollController = ScrollController();
  final _songs = <Song>[];

  PlaylistSummary? _info;
  var _nextPage = 1;
  var _hasMore = true;
  var _isInitialLoading = true;
  var _isLoadingMore = false;
  String? _errorMessage;
  String? _loadMoreError;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isInitialLoading = true;
      _isLoadingMore = false;
      _errorMessage = null;
      _loadMoreError = null;
      _nextPage = 1;
      _hasMore = true;
      _songs.clear();
    });

    try {
      final results = await Future.wait([
        widget.api.playlistInfo(widget.playlist.id),
        widget.api.playlistSongs(
          widget.playlist.id,
          page: 1,
          pageSize: _pageSize,
        ),
      ]);
      if (!mounted) return;

      final info = results[0] as PlaylistSummary;
      final songs = results[1] as List<Song>;
      setState(() {
        _info = info;
        _songs.addAll(songs);
        _nextPage = 2;
        _hasMore =
            _songs.length < (info.songCount ?? 1 << 31) &&
            songs.length == _pageSize;
        _isInitialLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isInitialLoading = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || !_hasMore || _isLoadingMore) {
      return;
    }

    final position = _scrollController.position;
    if (position.extentAfter < 520) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      final songs = await widget.api.playlistSongs(
        widget.playlist.id,
        page: _nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;

      setState(() {
        _songs.addAll(songs);
        _nextPage++;
        _hasMore =
            songs.length == _pageSize &&
            _songs.length < (_info?.songCount ?? 1 << 31);
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadMoreError = error.toString();
        _isLoadingMore = false;
      });
    }
  }

  PlaylistSummary get _currentPlaylist => _info ?? widget.playlist;

  PlaylistSummary get _libraryPlaylist {
    return widget.auth.findUserPlaylist(_currentPlaylist) ?? _currentPlaylist;
  }

  bool get _isInLibrary => widget.auth.isPlaylistInLibrary(_currentPlaylist);

  bool get _canEdit => widget.auth.canEditPlaylist(_currentPlaylist);

  Future<void> _collectPlaylist() async {
    await _runMutation(() => widget.auth.collectPlaylist(_currentPlaylist));
  }

  Future<void> _deleteOrUncollectPlaylist() async {
    final target = _libraryPlaylist;
    final title = target.isCreatedPlaylist ? '删除歌单' : '取消收藏';
    final message = target.isCreatedPlaylist ? '确定要删除这个歌单吗？' : '确定要取消收藏这个歌单吗？';
    final confirmed = await _confirm(title: title, message: message);
    if (confirmed != true) return;

    await _runMutation(() => widget.auth.deleteOrUncollectPlaylist(target));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _removeSong(Song song) async {
    final confirmed = await _confirm(title: '删除歌曲', message: '从当前歌单删除这首歌？');
    if (confirmed != true) return;
    await _runMutation(() async {
      await widget.auth.removeSongFromPlaylist(_libraryPlaylist, song);
      if (mounted) {
        setState(() => _songs.removeWhere((item) => item.id == song.id));
      }
    });
  }

  Future<void> _addSongToPlaylist(Song song) async {
    await showAddToPlaylistSheet(
      context: context,
      auth: widget.auth,
      song: song,
    );
  }

  Future<void> _runMutation(Future<void> Function() action) async {
    if (_isMutating) return;
    setState(() => _isMutating = true);
    try {
      await action();
      if (widget.auth.errorMessage != null) {
        throw Exception(widget.auth.errorMessage);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作完成')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 198,
            surfaceTintColor: Colors.transparent,
            title: Text(
              (_info ?? widget.playlist).title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            actions: [
              if (_isMutating)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                )
              else if (!_isInLibrary || !_libraryPlaylist.isLikedPlaylist)
                PopupMenuButton<_PlaylistAction>(
                  onSelected: (action) {
                    switch (action) {
                      case _PlaylistAction.collect:
                        _collectPlaylist();
                      case _PlaylistAction.deleteOrUncollect:
                        _deleteOrUncollectPlaylist();
                    }
                  },
                  itemBuilder: (context) => [
                    if (!_isInLibrary)
                      const PopupMenuItem(
                        value: _PlaylistAction.collect,
                        child: Text('收藏歌单'),
                      ),
                    if (_isInLibrary && !_libraryPlaylist.isLikedPlaylist)
                      PopupMenuItem(
                        value: _PlaylistAction.deleteOrUncollect,
                        child: Text(
                          _libraryPlaylist.isCreatedPlaylist ? '删除歌单' : '取消收藏',
                        ),
                      ),
                  ],
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: _HeroHeader(info: _info ?? widget.playlist),
            ),
          ),
          if (_isInitialLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage case final message?)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _DetailError(message: message, onRetry: _loadInitial),
            )
          else ...[
            SliverToBoxAdapter(
              child: _Actions(
                count: _info?.songCount ?? _songs.length,
                loadedCount: _songs.length,
                onPlay: _songs.isEmpty
                    ? null
                    : () => widget.player.playSong(
                        _songs.first,
                        queue: List<Song>.of(_songs),
                      ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverList.separated(
                itemCount: _songs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return _SongRow(
                    song: song,
                    index: index + 1,
                    player: widget.player,
                    canDelete: _canEdit,
                    onTap: () => widget.player.playSong(
                      song,
                      queue: List<Song>.of(_songs),
                    ),
                    onAddToPlaylist: () => _addSongToPlaylist(song),
                    onDelete: () => _removeSong(song),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: _LoadMoreFooter(
                hasMore: _hasMore,
                isLoading: _isLoadingMore,
                errorMessage: _loadMoreError,
                onRetry: _loadMore,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.info});

  final PlaylistSummary info;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? .28 : .18),
            const Color(0xFFDCEEFF).withValues(alpha: isDark ? .08 : .92),
            Theme.of(context).scaffoldBackgroundColor,
          ],
          stops: const [0, .58, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              final artworkSize = compact ? 90.0 : 102.0;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Artwork(
                    url: info.coverUrl,
                    size: artworkSize,
                    borderRadius: 16,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          info.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          info.subtitle ?? _detailMeta(info),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _detailMeta(info),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.count,
    required this.loadedCount,
    required this.onPlay,
  });

  final int count;
  final int loadedCount;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              loadedCount >= count
                  ? '$count 首歌曲'
                  : '已加载 $loadedCount / $count 首',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放全部'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.hasMore,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final bool hasMore;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 34),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('加载失败，点击重试'),
          ),
        ),
      );
    }

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 34),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
      child: Center(
        child: Text(
          hasMore ? '继续下滑加载更多' : '已加载全部',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.index,
    required this.player,
    required this.canDelete,
    required this.onTap,
    required this.onAddToPlaylist,
    required this.onDelete,
  });

  final Song song;
  final int index;
  final PlayerController player;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final active = player.currentSong?.hash == song.hash;
        final activeColor = colorScheme.primary;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: .09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 50,
                  child: Stack(
                    children: [
                      Artwork(url: song.coverUrl, size: 50, borderRadius: 9),
                      Positioned(
                        left: 4,
                        top: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .42),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            child: Text(
                              '$index',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: .78),
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                            ),
                          ),
                        ),
                      ),
                      if (active)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(alpha: .9),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: NowPlayingBadge(
                                active: active,
                                playing: player.isPlaying,
                                color: activeColor,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: active ? activeColor : null,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: active
                              ? activeColor.withValues(alpha: .72)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  formatDuration(song.duration),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: active
                        ? activeColor.withValues(alpha: .72)
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: '更多',
                  onPressed: () {
                    showSongActionSheet(
                      context: context,
                      song: song,
                      actions: [
                        SongSheetAction(
                          icon: Icons.playlist_add_rounded,
                          title: '添加到歌单',
                          onTap: onAddToPlaylist,
                        ),
                        if (canDelete)
                          SongSheetAction(
                            icon: Icons.delete_outline_rounded,
                            title: '从歌单删除',
                            danger: true,
                            onTap: onDelete,
                          ),
                      ],
                    );
                  },
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 42),
          const SizedBox(height: 12),
          Text('歌单加载失败', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

String _detailMeta(PlaylistSummary info) {
  final parts = <String>[];
  if (info.songCount != null) {
    parts.add('${info.songCount} 首歌');
  }
  if (info.playCount != null) {
    parts.add(_playCount(info.playCount));
  }
  return parts.isEmpty ? '来自 KA Music' : parts.join(' · ');
}

String _playCount(int? value) {
  if (value == null) {
    return '精选歌单';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1)} 万次播放';
  }
  return '$value 次播放';
}
