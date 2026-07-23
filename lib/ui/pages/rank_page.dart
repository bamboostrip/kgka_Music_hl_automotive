import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import '../widgets/song_action_sheets.dart';

/// 排行榜页面 —— 展示酷狗各类榜单，点击榜单查看歌曲列表。
class RankPage extends StatefulWidget {
  const RankPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage>
    with AutomaticKeepAliveClientMixin {
  Future<List<RankCategory>>? _future;
  Future<List<Song>>? _newSongsFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = widget.api.rankList(withSong: 3);
    _newSongsFuture = widget.api.newSongs();
  }

  Future<void> _refresh() async {
    final rankFuture = widget.api.rankList(withSong: 3);
    final songsFuture = widget.api.newSongs();
    setState(() {
      _future = rankFuture;
      _newSongsFuture = songsFuture;
    });
    // FutureBuilder 各自处理错误，这里只需等待完成，忽略异常
    try {
      await Future.wait([rankFuture, songsFuture], eagerError: false);
    } catch (_) {}
  }

  void _openRankDetail(RankCategory rank) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankDetailPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          rank: rank,
        ),
      ),
    );
  }

  int _crossAxisCount(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCarLandscape =
        size.width > size.height && ThemeController.instance.carModeEnabled;
    if (isCarLandscape) return (size.width / 200).floor().clamp(2, 5);
    return size.width >= 720 ? 3 : 2;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<RankCategory>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _RankSkeleton();
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return _RankError(
            message: snapshot.error.toString(),
            onRetry: _refresh,
          );
        }
        final ranks = snapshot.data ?? [];
        if (ranks.isEmpty) {
          return const _RankEmpty();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 新歌推荐区域
            _NewSongsSection(
              future: _newSongsFuture,
              player: widget.player,
              auth: widget.auth,
            ),
            // 榜单标题 + 刷新按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Row(
                children: [
                  const Text(
                    '排行榜',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // 榜单网格
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = _crossAxisCount(context);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: ranks.length,
                    itemBuilder: (context, index) {
                      final rank = ranks[index];
                      return _RankCard(
                        rank: rank,
                        onTap: () => _openRankDetail(rank),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 166),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 新歌推荐
// ---------------------------------------------------------------------------

class _NewSongsSection extends StatelessWidget {
  const _NewSongsSection({
    required this.future,
    required this.player,
    required this.auth,
  });

  final Future<List<Song>>? future;
  final PlayerController player;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Song>>(
      future: future,
      builder: (context, snapshot) {
        final songs = snapshot.data ?? [];
        if (songs.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (songs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fiber_new_rounded, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text(
                    '新歌推荐',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: '播放全部',
                    onPressed: () =>
                        player.playSong(songs.first, queue: songs),
                    icon: const Icon(Icons.play_arrow_rounded),
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(38),
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: songs.length > 10 ? 10 : songs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return _NewSongCard(
                      song: song,
                      onTap: () => player.playSong(song, queue: songs),
                      isPlaying: player.currentSong?.hash == song.hash &&
                          song.hash.isNotEmpty,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NewSongCard extends StatelessWidget {
  const _NewSongCard({
    required this.song,
    required this.onTap,
    required this.isPlaying,
  });

  final Song song;
  final VoidCallback onTap;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(url: song.coverUrl, size: 100, borderRadius: 10),
            const SizedBox(height: 6),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isPlaying ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank, required this.onTap});

  final RankCategory rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Artwork(
                  url: rank.imageUrl,
                  size: double.infinity,
                  borderRadius: 14,
                  icon: Icons.leaderboard_rounded,
                ),
                // 渐变遮罩
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(14),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: .72),
                        ],
                      ),
                    ),
                  ),
                ),
                // 榜单名称
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Text(
                    rank.rankName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                // 预览歌曲
                if (rank.songs.isNotEmpty)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 26,
                    child: Text(
                      rank.songs
                          .take(2)
                          .map((s) => s.title)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            rank.rankName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 榜单详情（歌曲列表）
// ---------------------------------------------------------------------------

class RankDetailPage extends StatefulWidget {
  const RankDetailPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.rank,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final RankCategory rank;

  @override
  State<RankDetailPage> createState() => _RankDetailPageState();
}

class _RankDetailPageState extends State<RankDetailPage> {
  final _scrollController = ScrollController();
  final _songs = <Song>[];
  var _page = 1;
  var _hasMore = true;
  var _isLoadingMore = false;
  var _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 如果榜单自带歌曲预览，先显示
    if (widget.rank.songs.isNotEmpty) {
      _songs.addAll(widget.rank.songs);
    }
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
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await widget.api.rankAudio(
        rankId: widget.rank.rankId,
        page: 1,
        pageSize: 50,
      );
      if (!mounted) return;
      setState(() {
        _songs
          ..clear()
          ..addAll(result.songs);
        _page = 2;
        _hasMore = result.songs.length >= 50;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || !_hasMore || _isLoadingMore) return;
    if (_scrollController.position.extentAfter < 400) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await widget.api.rankAudio(
        rankId: widget.rank.rankId,
        page: _page,
        pageSize: 50,
      );
      if (!mounted) return;
      setState(() {
        _songs.addAll(result.songs);
        _page++;
        _hasMore = result.songs.length >= 50;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _playSong(Song song) {
    widget.player.playSong(song, queue: List.of(_songs));
  }

  void _playAll() {
    if (_songs.isNotEmpty) {
      widget.player.playSong(_songs.first, queue: List.of(_songs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 200,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.rank.rankName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.rank.imageUrl != null)
                        Image.network(
                          widget.rank.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .1),
                              isDark
                                  ? const Color(0xFF06070A)
                                  : Colors.white,
                            ],
                            stops: const [0.3, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 播放全部按钮
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _playAll,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text('播放全部 (${_songs.length})'),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                      ),
                      const Spacer(),
                      if (_isLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),
              // 歌曲列表
              if (_error != null && _songs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '加载失败',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _loadInitial,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= _songs.length) {
                        return _isLoadingMore
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final song = _songs[index];
                      return _RankSongRow(
                        index: index + 1,
                        song: song,
                        onTap: () => _playSong(song),
                        auth: widget.auth,
                        player: widget.player,
                        queue: _songs,
                      );
                    },
                    childCount: _songs.length + (_hasMore ? 1 : 0),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 166)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 排行榜歌曲行
// ---------------------------------------------------------------------------

class _RankSongRow extends StatelessWidget {
  const _RankSongRow({
    required this.index,
    required this.song,
    required this.onTap,
    required this.auth,
    required this.player,
    required this.queue,
  });

  final int index;
  final Song song;
  final VoidCallback onTap;
  final AuthController auth;
  final PlayerController player;
  final List<Song> queue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTop3 = index <= 3;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final isPlaying =
            song.hash.isNotEmpty && player.currentSong?.hash == song.hash;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: () => showSongActionSheet(
            context: context,
            song: song,
            actions: [
              SongSheetAction(
                icon: Icons.queue_music_rounded,
                title: '下一首播放',
                onTap: () => addSongToQueueWithFeedback(
                  context: context,
                  player: player,
                  song: song,
                ),
              ),
              SongSheetAction(
                icon: Icons.playlist_add_rounded,
                title: '添加到歌单',
                onTap: () => showAddToPlaylistSheet(
                  context: context,
                  auth: auth,
                  song: song,
                ),
              ),
              if (player.downloadController != null)
                SongSheetAction(
                  icon: player.downloadController!.isDownloaded(song)
                      ? Icons.download_done_rounded
                      : Icons.download_rounded,
                  title: player.downloadController!.isDownloaded(song)
                      ? '已下载'
                      : '下载',
                  onTap: () => player.downloadController!
                      .download(song, player.audioQuality),
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // 排名
                SizedBox(
                  width: 32,
                  child: Text(
                    '$index',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isTop3 ? 16 : 14,
                      fontWeight: isTop3 ? FontWeight.w900 : FontWeight.w600,
                      color: isTop3
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontStyle: isTop3 ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 封面
                Artwork(url: song.coverUrl, size: 44, borderRadius: 8),
                const SizedBox(width: 12),
                // 歌曲信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isPlaying
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 播放图标
                if (isPlaying)
                  Icon(
                    Icons.equalizer_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  )
                else
                  Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 骨架屏 / 错误 / 空状态
// ---------------------------------------------------------------------------

class _RankSkeleton extends StatelessWidget {
  const _RankSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.72,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _RankError extends StatelessWidget {
  const _RankError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 12),
            Text(
              '加载失败',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _RankEmpty extends StatelessWidget {
  const _RankEmpty();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.leaderboard_rounded,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无榜单数据',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
