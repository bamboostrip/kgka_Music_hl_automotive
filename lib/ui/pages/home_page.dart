import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import 'playlist_detail_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static _HomeData? _cachedData;

  late Future<_HomeData> _future;
  var _sectionIndex = 0;

  @override
  void initState() {
    super.initState();
    final cached = _cachedData;
    _future = cached == null ? _load() : Future.value(cached);
  }

  Future<_HomeData> _load() async {
    final results = await Future.wait([
      widget.api.dailyRecommend(),
      widget.api.recommendedPlaylists(),
    ]);
    final data = _HomeData(
      daily: results[0] as DailyRecommend,
      playlists: results[1] as List<PlaylistSummary>,
    );
    _cachedData = data;
    return data;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  void _openPlaylist(PlaylistSummary playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailPage(
          api: widget.api,
          player: widget.player,
          playlist: playlist,
        ),
      ),
    );
  }

  void _playSong(Song song, List<Song> queue) {
    widget.player.playSong(song, queue: queue);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _cachedData;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (data == null &&
                  snapshot.connectionState == ConnectionState.waiting)
                const SliverToBoxAdapter(child: _HomeSkeleton())
              else if (data == null && snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorView(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _RecommendHeader(
                    auth: widget.auth,
                    daily: data!.daily,
                    sectionIndex: _sectionIndex,
                    onSectionChanged: (value) {
                      setState(() => _sectionIndex = value);
                    },
                    onDailyPlay: () {
                      final songs = data.daily.songs;
                      if (songs.isNotEmpty) {
                        widget.player.playSong(songs.first, queue: songs);
                      }
                    },
                    api: widget.api,
                    player: widget.player,
                  ),
                ),
                if (_sectionIndex == 1)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _RadioUnsupported(),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: _SongSection(
                      title: '母带音质·精选',
                      songs: data.daily.songs,
                      onPlay: _playSong,
                      isLiked: (song) => widget.auth.isLiked(song),
                      onLikeTap: (song) => widget.auth.toggleLike(song),
                      auth: widget.auth,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _PlaylistRail(
                      playlists: data.playlists,
                      onTap: _openPlaylist,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 166)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecommendHeader extends StatelessWidget {
  const _RecommendHeader({
    required this.auth,
    required this.daily,
    required this.sectionIndex,
    required this.onSectionChanged,
    required this.onDailyPlay,
    required this.api,
    required this.player,
  });

  final AuthController auth;
  final DailyRecommend daily;
  final int sectionIndex;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onDailyPlay;
  final MusicApi api;
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF10233A), Color(0xFF06070A)]
              : const [Color(0xFFDCEEFF), Color(0xFFF7FBFF), Colors.white],
          stops: isDark ? const [0, 1] : const [0, .68, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 0, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 18),
                child: _TopTabs(
                  auth: auth,
                  index: sectionIndex,
                  onChanged: onSectionChanged,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(right: 18),
                child: _SmartSearch(api: api, auth: auth, player: player),
              ),
              const SizedBox(height: 14),
              _FeatureShelf(daily: daily, onDailyPlay: onDailyPlay),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({
    required this.auth,
    required this.index,
    required this.onChanged,
  });

  final AuthController auth;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabs = ['推荐', '电台'];
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        return Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in tabs.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 30),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(entry.$1),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                entry.$2,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontSize: 18,
                                      color: entry.$1 == index
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: entry.$1 == index
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: entry.$1 == index ? 28 : 0,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 38,
              height: 38,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: auth.profile?.avatarUrl == null
                  ? const Icon(Icons.group_rounded, color: Colors.white)
                  : Image.network(auth.profile!.avatarUrl!, fit: BoxFit.cover),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '菜单',
              onPressed: () {},
              icon: const Icon(Icons.menu_rounded),
            ),
          ],
        );
      },
    );
  }
}

class _SmartSearch extends StatelessWidget {
  const _SmartSearch({
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(api: api, auth: auth, player: player),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _openSearch(context),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: .08)
                    : Colors.white.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white.withValues(alpha: .56)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  '搜索歌曲，歌手',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureShelf extends StatelessWidget {
  const _FeatureShelf({required this.daily, required this.onDailyPlay});

  final DailyRecommend daily;
  final VoidCallback onDailyPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardSize = (constraints.maxWidth - 10) / 2;
          return SizedBox(
            height: cardSize,
            child: Row(
              children: [
                Expanded(
                  child: _FeatureCard(
                    title: '猜你喜欢',
                    subtitle: daily.songs.isEmpty
                        ? '献给此刻迈步的你'
                        : daily.songs.first.title,
                    imageUrl: daily.songs.isEmpty
                        ? daily.coverUrl
                        : daily.songs.first.coverUrl,
                    gradient: const [Color(0xFFFFD88E), Color(0xFFFF8DA2)],
                    onTap: onDailyPlay,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FeatureCard(
                    title: '每日推荐',
                    subtitle: daily.songs.length > 1
                        ? daily.songs[1].title
                        : daily.title,
                    imageUrl: daily.songs.length > 1
                        ? daily.songs[1].coverUrl
                        : (daily.songs.isEmpty
                              ? daily.coverUrl
                              : daily.songs.first.coverUrl),
                    gradient: const [Color(0xFF454A92), Color(0xFF78CAFF)],
                    onTap: onDailyPlay,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              if (imageUrl != null)
                Positioned.fill(
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .16),
                        Colors.black.withValues(alpha: .54),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 13,
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white.withValues(alpha: .94),
                  size: 32,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .82),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongSection extends StatelessWidget {
  const _SongSection({
    required this.title,
    required this.songs,
    required this.onPlay,
    required this.isLiked,
    required this.onLikeTap,
    required this.auth,
  });

  final String title;
  final List<Song> songs;
  final void Function(Song song, List<Song> queue) onPlay;
  final bool Function(Song song) isLiked;
  final void Function(Song song) onLikeTap;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleSongs = songs.take(8).toList();
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            children: [
              _SectionHeader(
                title: title,
                action: IconButton.filledTonal(
                  tooltip: '播放',
                  onPressed: () => onPlay(visibleSongs.first, songs),
                  icon: const Icon(Icons.play_arrow_rounded),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(42),
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final song in visibleSongs)
                _HomeSongRow(
                  song: song,
                  queue: songs,
                  onPlay: onPlay,
                  isLiked: isLiked(song),
                  onLikeTap: () => onLikeTap(song),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeSongRow extends StatelessWidget {
  const _HomeSongRow({
    required this.song,
    required this.queue,
    required this.onPlay,
    required this.isLiked,
    required this.onLikeTap,
  });

  final Song song;
  final List<Song> queue;
  final void Function(Song song, List<Song> queue) onPlay;
  final bool isLiked;
  final VoidCallback onLikeTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onPlay(song, queue),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Artwork(url: song.coverUrl, size: 58, borderRadius: 8),
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
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: onLikeTap,
              icon: Icon(
                isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isLiked ? Colors.redAccent : colorScheme.outline,
                size: 27,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRail extends StatelessWidget {
  const _PlaylistRail({required this.playlists, required this.onTap});

  final List<PlaylistSummary> playlists;
  final ValueChanged<PlaylistSummary> onTap;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _SectionHeader(
              title: '推荐歌单',
              action: Icon(
                Icons.more_horiz_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 204,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return _PlaylistCard(
                  playlist: playlist,
                  onTap: () => onTap(playlist),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        action,
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(url: playlist.coverUrl, size: 128, borderRadius: 10),
            const SizedBox(height: 9),
            SizedBox(
              height: 42,
              child: Text(
                playlist.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.16,
                ),
              ),
            ),
            Text(
              playlist.subtitle ?? _playCount(playlist.playCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioUnsupported extends StatelessWidget {
  const _RadioUnsupported();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 54, 28, 166),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.radio_rounded,
            size: 42,
            color: colorScheme.primary.withValues(alpha: .72),
          ),
          const SizedBox(height: 14),
          Text(
            '电台暂不支持',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '等接口准备好后再接入这个频道。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 166),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _SkeletonBox(width: 54, height: 26, radius: 8),
                const SizedBox(width: 26),
                const _SkeletonBox(width: 42, height: 26, radius: 8),
                const Spacer(),
                _SkeletonBox.circle(size: 38),
                const SizedBox(width: 12),
                _SkeletonBox.circle(size: 34),
              ],
            ),
            const SizedBox(height: 28),
            const _SkeletonBox(width: double.infinity, height: 44, radius: 9),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardSize = (constraints.maxWidth - 10) / 2;
                return Row(
                  children: [
                    _SkeletonBox(width: cardSize, height: cardSize, radius: 12),
                    const SizedBox(width: 10),
                    _SkeletonBox(width: cardSize, height: cardSize, radius: 12),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            const _SkeletonBox(width: 128, height: 24, radius: 8),
            const SizedBox(height: 18),
            for (var index = 0; index < 6; index++) ...[
              Row(
                children: [
                  const _SkeletonBox(width: 58, height: 58, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _SkeletonBox(
                          width: double.infinity,
                          height: 16,
                          radius: 6,
                        ),
                        SizedBox(height: 8),
                        _SkeletonBox(width: 140, height: 14, radius: 6),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  const _SkeletonBox.circle({required double size})
    : width = size,
      height = size,
      radius = size / 2;

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text('暂时连接不上音乐服务', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),
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

class _HomeData {
  const _HomeData({required this.daily, required this.playlists});

  final DailyRecommend daily;
  final List<PlaylistSummary> playlists;
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
