import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/app_version.dart';
import '../../models/music_models.dart';
import '../../services/app_update_service.dart';
import '../../services/cache_service.dart';
import '../../services/music_api.dart';
import '../widgets/app_update_widgets.dart';
import '../widgets/artwork.dart';
import '../widgets/now_playing_badge.dart';
import '../widgets/song_action_sheets.dart';
import '../widgets/toast.dart';
import 'album_shop_page.dart';
import 'artist_detail_page.dart';
import 'playlist_detail_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.cache,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final CacheService cache;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static _HomeData? _cachedData;

  Future<_HomeData>? _future;
  late final AppUpdateService _updateService;
  AppVersionInfo? _availableUpdate;
  var _sectionIndex = 0;
  var _updateBannerDismissed = false;
  var _autoUpdateDialogShown = false;

  @override
  void initState() {
    super.initState();
    _updateService = AppUpdateService(widget.api);
    final cached = _cachedData;
    if (cached != null) {
      _future = Future.value(cached);
      // 有缓存数据，立即显示并后台静默刷新
      _silentRefresh();
    } else if (!widget.auth.isRestoring) {
      _future = _load();
    } else {
      _tryRestoreFromCache();
    }
    widget.auth.addListener(_handleAuthChanged);
    if (AppUpdateService.isSupportedPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (widget.auth.isRestoring || !widget.auth.isLoggedIn) {
      return;
    }
    // 首次加载（无缓存）或 auth 恢复完成后触发加载
    if (_future == null) {
      setState(() {
        _future = _load();
      });
    }
  }

  /// 后台静默刷新首页数据。
  ///
  /// 先从缓存显示（已在 initState/_tryRestoreFromCache 中完成），
  /// 然后后台请求最新数据，成功后更新 UI，失败则保持缓存数据。
  Future<void> _silentRefresh() async {
    try {
      final results = await Future.wait([
        widget.api.dailyRecommend(),
        widget.api.recommendedPlaylists(),
        widget.api.albumShop(),
      ]);
      if (!mounted) return;
      final data = _HomeData(
        daily: results[0] as DailyRecommend,
        playlists: results[1] as List<PlaylistSummary>,
        albums: results[2] as List<AlbumShopItem>,
      );
      _cachedData = data;
      await widget.cache.write('cache_home', {
        'daily': data.daily.toCache(),
        'playlists': data.playlists.map((p) => p.toCache()).toList(),
        'albums': data.albums.map((a) => a.toCache()).toList(),
      });
      if (!mounted) return;
      setState(() {
        _future = Future.value(data);
      });
    } catch (_) {
      // 静默刷新失败，保持缓存数据不变
    }
  }

  Future<_HomeData> _load() async {
    final results = await Future.wait([
      widget.api.dailyRecommend(),
      widget.api.recommendedPlaylists(),
      widget.api.albumShop(),
    ]);
    final data = _HomeData(
      daily: results[0] as DailyRecommend,
      playlists: results[1] as List<PlaylistSummary>,
      albums: results[2] as List<AlbumShopItem>,
    );
    _cachedData = data;
    await widget.cache.write('cache_home', {
      'daily': data.daily.toCache(),
      'playlists': data.playlists.map((p) => p.toCache()).toList(),
      'albums': data.albums.map((a) => a.toCache()).toList(),
    });
    return data;
  }

  Future<void> _tryRestoreFromCache() async {
    final cached = await widget.cache.read<Map<String, dynamic>>(
      'cache_home',
      decode: (json) => json,
      ttl: AppConfig.homeCacheTtl,
    );
    if (!mounted || _future != null) return;
    if (cached != null) {
      final data = _homeDataFromCache(cached.data);
      _cachedData = data;
      setState(() {
        _future = Future.value(data);
      });
      // 缓存数据已显示，后台静默刷新
      _silentRefresh();
    } else {
      // 无缓存数据，直接从网络加载
      setState(() {
        _future = _load();
      });
    }
  }

  _HomeData _homeDataFromCache(Map<String, dynamic> json) {
    return _HomeData(
      daily: DailyRecommend.fromCache(json['daily'] as Map<String, dynamic>),
      playlists: (json['playlists'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlaylistSummary.fromCache)
          .toList(),
      albums: (json['albums'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AlbumShopItem.fromCache)
          .toList(),
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _checkForUpdates() async {
    try {
      final version = await _updateService.checkForUpdate();
      if (!mounted || version == null) {
        return;
      }

      if (version.forceUpdate) {
        if (_autoUpdateDialogShown) {
          return;
        }
        _autoUpdateDialogShown = true;
        await showAppUpdateDialog(
          context: context,
          service: _updateService,
          version: version,
          force: true,
        );
        return;
      }

      if (!_updateBannerDismissed) {
        setState(() => _availableUpdate = version);
      }
    } catch (_) {
      // The automatic check should stay quiet; manual checks surface errors.
    }
  }

  Future<void> _showUpdateDetails() {
    final version = _availableUpdate;
    if (version == null) {
      return Future.value();
    }
    return showAppUpdateDialog(
      context: context,
      service: _updateService,
      version: version,
      force: false,
    );
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

  void _playSong(Song song, List<Song> queue) {
    widget.player.playSong(song, queue: queue);
  }

  void _openArtist(Song song) {
    final artist = song.artists.firstWhere(
      (a) => a.name.isNotEmpty,
      orElse: () => const ArtistRef(id: '', name: ''),
    );
    if (artist.name.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistDetailPage(
          api: widget.api,
          auth: widget.auth,
          artist: artist,
          player: widget.player,
        ),
      ),
    );
  }

  void _openAlbumShop() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumShopPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          initialAlbums: _cachedData?.albums ?? [],
        ),
      ),
    );
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
                  (_future == null ||
                      snapshot.connectionState == ConnectionState.waiting))
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
                    albums: data.albums,
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
                    onAlbumTap: _openAlbumShop,
                    api: widget.api,
                    player: widget.player,
                    updateVersion: _updateBannerDismissed
                        ? null
                        : _availableUpdate,
                    onUpdateTap: () {
                      _showUpdateDetails();
                    },
                    onUpdateClose: () {
                      setState(() => _updateBannerDismissed = true);
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _PersistentTabPane(
                        visible: _sectionIndex == 0,
                        child: Column(
                          children: [
                            _SongSection(
                              title: '母带音质·精选',
                              songs: data.daily.songs,
                              onPlay: _playSong,
                              isLiked: (song) => widget.auth.isLiked(song),
                              onLikeTap: (song) => widget.auth.toggleLike(song),
                              auth: widget.auth,
                              player: widget.player,
                              onViewArtist: _openArtist,
                            ),
                            _PlaylistRail(
                              playlists: data.playlists,
                              onTap: _openPlaylist,
                            ),
                          ],
                        ),
                      ),
                      _PersistentTabPane(
                        visible: _sectionIndex == 1,
                        child: _RadioSection(
                          api: widget.api,
                          player: widget.player,
                        ),
                      ),
                    ],
                  ),
                ),
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
    required this.albums,
    required this.sectionIndex,
    required this.onSectionChanged,
    required this.onDailyPlay,
    required this.onAlbumTap,
    required this.api,
    required this.player,
    required this.updateVersion,
    required this.onUpdateTap,
    required this.onUpdateClose,
  });

  final AuthController auth;
  final DailyRecommend daily;
  final List<AlbumShopItem> albums;
  final int sectionIndex;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onDailyPlay;
  final VoidCallback onAlbumTap;
  final MusicApi api;
  final PlayerController player;
  final AppVersionInfo? updateVersion;
  final VoidCallback onUpdateTap;
  final VoidCallback onUpdateClose;

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
              if (updateVersion != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: AppUpdateBanner(
                    version: updateVersion!,
                    onTap: onUpdateTap,
                    onClose: onUpdateClose,
                  ),
                ),
              ],
              if (sectionIndex == 0) ...[
                const SizedBox(height: 14),
                _FeatureShelf(
                  daily: daily,
                  albums: albums,
                  onDailyPlay: onDailyPlay,
                  onAlbumTap: onAlbumTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PersistentTabPane extends StatelessWidget {
  const _PersistentTabPane({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: visible,
      child: Offstage(offstage: !visible, child: child),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
  const _FeatureShelf({
    required this.daily,
    required this.albums,
    required this.onDailyPlay,
    required this.onAlbumTap,
  });

  final DailyRecommend daily;
  final List<AlbumShopItem> albums;
  final VoidCallback onDailyPlay;
  final VoidCallback onAlbumTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardSize = (constraints.maxWidth - 10) / 2;
          return SizedBox(
            height: cardSize.clamp(140.0, 200.0),
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
                  child: albums.isNotEmpty
                      ? _FeatureCard(
                          title: '新碟上架',
                          subtitle: '${albums.first.singerName} · ${albums.first.albumName}',
                          imageUrl: albums.first.coverUrl,
                          gradient: const [Color(0xFF454A92), Color(0xFF78CAFF)],
                          onTap: onAlbumTap,
                        )
                      : _FeatureCard(
                          title: '新碟上架',
                          subtitle: '暂无新专辑',
                          imageUrl: null,
                          gradient: const [Color(0xFF454A92), Color(0xFF78CAFF)],
                          onTap: () {},
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
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
                        fontSize: 16,
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

class _SongSection extends StatefulWidget {
  const _SongSection({
    required this.title,
    required this.songs,
    required this.onPlay,
    required this.isLiked,
    required this.onLikeTap,
    required this.auth,
    required this.player,
    required this.onViewArtist,
  });

  final String title;
  final List<Song> songs;
  final void Function(Song song, List<Song> queue) onPlay;
  final bool Function(Song song) isLiked;
  final void Function(Song song) onLikeTap;
  final AuthController auth;
  final PlayerController player;
  final void Function(Song song) onViewArtist;

  @override
  State<_SongSection> createState() => _SongSectionState();
}

class _SongSectionState extends State<_SongSection> {
  static const _perPage = 5;
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _pageCount => (widget.songs.length / _perPage).ceil();

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 720;
    final rowCount = isWide ? (_perPage / 2).ceil() : _perPage;

    return AnimatedBuilder(
      animation: widget.auth,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            children: [
              _SectionHeader(
                title: widget.title,
                action: IconButton.filledTonal(
                  tooltip: '播放',
                  onPressed: () =>
                      widget.onPlay(widget.songs.first, widget.songs),
                  icon: const Icon(Icons.play_arrow_rounded),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(42),
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: rowCount * 76.0,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pageCount,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, pageIndex) {
                    final start = pageIndex * _perPage;
                    final end = (start + _perPage).clamp(0, widget.songs.length);
                    final pageSongs = widget.songs.sublist(start, end);

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                for (var i = 0; i < pageSongs.length; i += 2)
                                  _HomeSongRow(
                                    song: pageSongs[i],
                                    queue: widget.songs,
                                    onPlay: widget.onPlay,
                                    isLiked: widget.isLiked(pageSongs[i]),
                                    onLikeTap: () => widget.onLikeTap(pageSongs[i]),
                                    auth: widget.auth,
                                    player: widget.player,
                                    onViewArtist: () => widget.onViewArtist(pageSongs[i]),
                                  ),
                              ],
                            ),
                          ),
                          if (pageSongs.length > 1) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: [
                                  for (var i = 1; i < pageSongs.length; i += 2)
                                    _HomeSongRow(
                                      song: pageSongs[i],
                                      queue: widget.songs,
                                      onPlay: widget.onPlay,
                                      isLiked: widget.isLiked(pageSongs[i]),
                                      onLikeTap: () => widget.onLikeTap(pageSongs[i]),
                                      auth: widget.auth,
                                      player: widget.player,
                                      onViewArtist: () => widget.onViewArtist(pageSongs[i]),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    }

                    return Column(
                      children: [
                        for (final song in pageSongs)
                          _HomeSongRow(
                            song: song,
                            queue: widget.songs,
                            onPlay: widget.onPlay,
                            isLiked: widget.isLiked(song),
                            onLikeTap: () => widget.onLikeTap(song),
                            auth: widget.auth,
                            player: widget.player,
                            onViewArtist: () => widget.onViewArtist(song),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_pageCount > 1) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pageCount, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: active ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ],
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
    required this.auth,
    required this.player,
    required this.onViewArtist,
  });

  final Song song;
  final List<Song> queue;
  final void Function(Song song, List<Song> queue) onPlay;
  final bool isLiked;
  final VoidCallback onLikeTap;
  final AuthController auth;
  final PlayerController player;
  final VoidCallback onViewArtist;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final active =
            song.hash.isNotEmpty && player.currentSong?.hash == song.hash;
        final activeColor = colorScheme.primary;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onPlay(song, queue),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    Artwork(url: song.coverUrl, size: 58, borderRadius: 8),
                    if (active)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: .88),
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
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: active
                              ? activeColor.withValues(alpha: .72)
                              : colorScheme.onSurfaceVariant,
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
                    isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isLiked ? Colors.redAccent : colorScheme.outline,
                    size: 27,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: '更多',
                  onPressed: () {
                    showSongActionSheet(
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
                        SongSheetAction(
                          icon: Icons.person_rounded,
                          title: '查看歌手',
                          onTap: onViewArtist,
                        ),
                        if (player.downloadController != null)
                          SongSheetAction(
                            icon: player.downloadController!.isDownloaded(song)
                                ? Icons.download_done_rounded
                                : Icons.download_rounded,
                            title: player.downloadController!.isDownloaded(song)
                                ? '已下载'
                                : '下载',
                            onTap: () => player.downloadController!.download(
                              song,
                              player.audioQuality,
                            ),
                          ),
                      ],
                    );
                  },
                  icon: const Icon(Icons.more_horiz_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        );
      },
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
              action: const SizedBox.shrink(),
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

class _RadioSection extends StatefulWidget {
  const _RadioSection({required this.api, required this.player});

  final MusicApi api;
  final PlayerController player;

  @override
  State<_RadioSection> createState() => _RadioSectionState();
}

class _RadioSectionState extends State<_RadioSection> {
  static Future<_RadioData>? _cachedFuture;

  late Future<_RadioData> _future;
  String? _loadingStationId;

  @override
  void initState() {
    super.initState();
    _future = _cachedFuture ??= _load();
  }

  Future<_RadioData> _load() async {
    final results = await Future.wait([
      widget.api.fmRecommendedStations(),
      widget.api.fmClassGroups(),
    ]);
    final recommended = results[0] as List<FmStation>;
    final groups = results[1] as List<FmClassGroup>;
    final imageIds =
        [...recommended, ...groups.expand((group) => group.stations.take(4))]
            .where((station) => station.artworkUrl == null)
            .map((station) => station.id)
            .toList();
    final images = await widget.api.fmImages(imageIds);

    FmStation applyImage(FmStation station) {
      final image = images[station.id];
      return image == null ? station : station.mergeImage(image);
    }

    return _RadioData(
      recommended: recommended.map(applyImage).toList(),
      groups: groups
          .map(
            (group) => FmClassGroup(
              id: group.id,
              name: group.name,
              stations: group.stations.map(applyImage).toList(),
            ),
          )
          .toList(),
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    _cachedFuture = future;
    setState(() { _future = future; });
    await future;
  }

  Future<void> _playStation(FmStation station) async {
    if (_loadingStationId != null) {
      return;
    }

    setState(() => _loadingStationId = station.id);
    try {
      final songs = await widget.api.fmSongs(station);
      final queue = songs.isEmpty ? station.previewSongs : songs;
      if (!mounted) {
        return;
      }
      if (queue.isEmpty) {
        Toast.info('这个电台暂时没有可播放歌曲');
        return;
      }
      widget.player.playSong(queue.first, queue: queue);
    } catch (error) {
      if (!mounted) {
        return;
      }
      Toast.error('电台加载失败：$error');
    } finally {
      if (mounted) {
        setState(() => _loadingStationId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RadioData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            data == null) {
          return const _RadioSkeleton();
        }
        if (data == null && snapshot.hasError) {
          return _ErrorView(
            message: snapshot.error.toString(),
            onRetry: _refresh,
          );
        }
        final radio = data ?? _RadioData.empty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: '推荐电台',
                action: IconButton.filledTonal(
                  tooltip: '刷新',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(42),
                    shape: const CircleBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (radio.recommended.isNotEmpty)
                _RadioHeroCard(
                  station: radio.recommended.first,
                  loading: _loadingStationId == radio.recommended.first.id,
                  onTap: () => _playStation(radio.recommended.first),
                ),
              if (radio.recommended.length > 1) ...[
                const SizedBox(height: 14),
                _RadioStationRail(
                  stations: radio.recommended.skip(1).toList(),
                  loadingStationId: _loadingStationId,
                  onTap: _playStation,
                ),
              ],
              for (final group in radio.groups) ...[
                const SizedBox(height: 24),
                _SectionHeader(
                  title: group.name,
                  action: Icon(
                    Icons.radio_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _RadioStationRail(
                  stations: group.stations,
                  loadingStationId: _loadingStationId,
                  onTap: _playStation,
                ),
              ],
              if (radio.recommended.isEmpty && radio.groups.isEmpty)
                const _RadioEmpty(),
            ],
          ),
        );
      },
    );
  }
}

class _RadioHeroCard extends StatelessWidget {
  const _RadioHeroCard({
    required this.station,
    required this.loading,
    required this.onTap,
  });

  final FmStation station;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.08,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (station.bannerUrl ?? station.artworkUrl case final url?)
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .08),
                        Colors.black.withValues(alpha: .72),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        station.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: .82),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: _RadioPlayBadge(loading: loading),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioStationRail extends StatelessWidget {
  const _RadioStationRail({
    required this.stations,
    required this.loadingStationId,
    required this.onTap,
  });

  final List<FmStation> stations;
  final String? loadingStationId;
  final ValueChanged<FmStation> onTap;

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 182,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 13),
        itemBuilder: (context, index) {
          final station = stations[index];
          return _RadioStationCard(
            station: station,
            loading: loadingStationId == station.id,
            onTap: () => onTap(station),
          );
        },
      ),
    );
  }
}

class _RadioStationCard extends StatelessWidget {
  const _RadioStationCard({
    required this.station,
    required this.loading,
    required this.onTap,
  });

  final FmStation station;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 128,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: loading ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Artwork(url: station.artworkUrl, size: 128, borderRadius: 10),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: .42),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _RadioPlayBadge(loading: loading, compact: true),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              station.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.16,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              station.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioPlayBadge extends StatelessWidget {
  const _RadioPlayBadge({required this.loading, this.compact = false});

  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 42.0;
    return SizedBox(
      width: size,
      height: size,
      child: loading
          ? Center(
              child: SizedBox.square(
                dimension: compact ? 16 : 20,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              ),
            )
          : Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: compact ? 22 : 30,
              shadows: const [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
    );
  }
}

class _RadioSkeleton extends StatelessWidget {
  const _RadioSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonBox(width: 112, height: 24, radius: 8),
          const SizedBox(height: 14),
          const _SkeletonBox(width: double.infinity, height: 170, radius: 14),
          const SizedBox(height: 22),
          const _SkeletonBox(width: 90, height: 22, radius: 8),
          const SizedBox(height: 12),
          SizedBox(
            height: 164,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 13),
              itemBuilder: (context, index) {
                return _SkeletonBox(
                  width: index == 2 ? 76 : 128,
                  height: 164,
                  radius: 10,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RadioEmpty extends StatelessWidget {
  const _RadioEmpty();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 46, 10, 70),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.radio_rounded,
              size: 42,
              color: colorScheme.primary.withValues(alpha: .72),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无电台内容',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
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
  const _HomeData({
    required this.daily,
    required this.playlists,
    required this.albums,
  });

  final DailyRecommend daily;
  final List<PlaylistSummary> playlists;
  final List<AlbumShopItem> albums;
}

class _RadioData {
  const _RadioData({required this.recommended, required this.groups});

  static const empty = _RadioData(recommended: [], groups: []);

  final List<FmStation> recommended;
  final List<FmClassGroup> groups;
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
