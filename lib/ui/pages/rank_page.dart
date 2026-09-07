import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../../services/cache_service.dart';
import '../../services/music_api.dart';
import '../../services/network_monitor.dart';
import '../adaptive_layout.dart';
import '../form_factor.dart';
import '../widgets/app_feedback.dart' show friendlyServiceErrorMessage;
import '../widgets/artwork.dart';
import '../widgets/horizontal_wheel_scroll.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_action_sheets.dart';
import '../player/song_tap_handler.dart';
import '../widgets/desktop_song_table_row.dart'
    show DesktopSongTableHeader, DesktopSongTableRow;
import 'artist_detail_page.dart';

/// 排行榜页面 —— 展示酷狗各类榜单，点击榜单查看歌曲列表。
class RankPage extends StatefulWidget {
  const RankPage({
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
  State<RankPage> createState() => RankPageState();
}

class RankPageState extends State<RankPage>
    with AutomaticKeepAliveClientMixin {
  static List<RankCategory>? _cachedRanks;
  static List<Song>? _cachedNewSongs;

  Future<List<RankCategory>>? _future;
  Future<List<Song>>? _newSongsFuture;
  StreamSubscription<void>? _networkRestoredSub;
  bool _silentRefreshing = false;

  /// 加载代数：refresh / _silentRefresh / _initFromDiskOrNetwork 任一入口
  /// 开启新一轮加载时自增。旧代数的响应晚到时（如静默刷新与双击刷新并发）
  /// 不再写内存/磁盘缓存、不再覆盖 UI，避免旧数据倒灌覆盖新数据。
  int _loadEpoch = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cachedRanks = _cachedRanks;
    final cachedSongs = _cachedNewSongs;
    if (cachedRanks != null) {
      _future = Future.value(cachedRanks);
      _newSongsFuture = Future.value(cachedSongs ?? const <Song>[]);
      // 有内存缓存：立即显示并后台静默刷新（与推荐页一致）。
      _silentRefresh();
    } else {
      // 无内存缓存：先读磁盘再决定是否走网络，避免冷启动时网络与静默刷新重复请求。
      _future = null;
      _newSongsFuture = null;
      _initFromDiskOrNetwork();
    }
    // 断网进入排行榜会停留在错误/缓存页上，恢复网络后自动刷新。
    _networkRestoredSub = NetworkMonitor.instance.onConnectivityRestored.listen(
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    _networkRestoredSub?.cancel();
    super.dispose();
  }

  /// [epoch] 为发起本请求时的代数；响应返回时若已被更新一轮加载取代，
  /// 则跳过缓存写入（返回值仍交给调用方按代数决定是否上屏）。
  Future<List<RankCategory>> _loadRanks({int? epoch}) async {
    final ranks = await widget.api.rankList(withSong: 3);
    if (epoch == null || epoch == _loadEpoch) {
      _cachedRanks = ranks;
      _persistRanks(ranks);
    }
    return ranks;
  }

  void _persistRanks(List<RankCategory> ranks) {
    unawaited(() async {
      try {
        await widget.cache.write('cache_rank', {
          'ranks': ranks.map((r) => r.toCache()).toList(),
        });
      } catch (_) {
        // 缓存写入失败不影响已拿到的网络数据上屏。
      }
    }());
  }

  void _persistNewSongs(List<Song> songs) {
    unawaited(() async {
      try {
        await widget.cache.write('cache_rank_new', {
          'songs': songs.map((s) => s.toCache()).toList(),
        });
      } catch (_) {
        // 缓存写入失败不影响已拿到的网络数据上屏。
      }
    }());
  }

  /// 新歌推荐失败不阻塞榜单：无缓存时返回空（隐藏该区域），有缓存时降级到缓存。
  Future<List<Song>> _loadNewSongs({int? epoch}) async {
    try {
      final songs = await widget.api.newSongs();
      if (epoch == null || epoch == _loadEpoch) {
        _cachedNewSongs = songs;
        _persistNewSongs(songs);
      }
      return songs;
    } catch (_) {
      return _cachedNewSongs ?? const <Song>[];
    }
  }

  /// 冷启动单 flight：先读磁盘，命中则显示缓存+静默刷新，未命中才走网络。
  Future<void> _initFromDiskOrNetwork() async {
    final epoch = ++_loadEpoch;
    try {
      final results = await Future.wait([
        widget.cache.read<Map<String, dynamic>>(
          'cache_rank',
          decode: (json) => json,
          ttl: AppConfig.rankCacheTtl,
        ),
        widget.cache.read<Map<String, dynamic>>(
          'cache_rank_new',
          decode: (json) => json,
          ttl: AppConfig.rankCacheTtl,
        ),
      ]);
      // 磁盘读取期间用户已手动刷新（epoch 变化）：让位，不再回写缓存态。
      if (!mounted || epoch != _loadEpoch) return;
      final rankCache = results[0];
      final songsCache = results[1];
      if (rankCache != null) {
        try {
          final ranks = (rankCache.data['ranks'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(RankCategory.fromCache)
              .toList();
          if (ranks.isNotEmpty) {
            _cachedRanks = ranks;
            if (songsCache != null) {
              try {
                _cachedNewSongs =
                    (songsCache.data['songs'] as List? ?? const [])
                        .whereType<Map<String, dynamic>>()
                        .map(Song.fromCache)
                        .where((s) => s.hash.isNotEmpty)
                        .toList();
              } catch (_) {
                // 新歌缓存损坏则忽略，静默刷新会重建。
              }
            }
            setState(() {
              _future = Future.value(ranks);
              _newSongsFuture =
                  Future.value(_cachedNewSongs ?? const <Song>[]);
            });
            _silentRefresh();
            return;
          }
        } catch (_) {
          // 榜单缓存损坏则继续走网络。
        }
      } else if (songsCache != null) {
        // 榜单无缓存但新歌有缓存：先恢复新歌，避免网络回来后新歌区闪烁。
        try {
          _cachedNewSongs = (songsCache.data['songs'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(Song.fromCache)
              .where((s) => s.hash.isNotEmpty)
              .toList();
        } catch (_) {
          // 忽略损坏的新歌缓存。
        }
      }
    } catch (_) {
      // 磁盘读取失败则继续走网络。
    }
    if (!mounted || epoch != _loadEpoch) return;
    final rankFuture = _loadRanks(epoch: epoch);
    final songsFuture = _loadNewSongs(epoch: epoch);
    setState(() {
      _future = rankFuture;
      _newSongsFuture = songsFuture;
    });
  }

  /// 后台静默刷新：成功更新 UI 与缓存，失败保持缓存不变（与推荐页一致）。
  Future<void> _silentRefresh() async {
    if (_silentRefreshing) return;
    final epoch = ++_loadEpoch;
    _silentRefreshing = true;
    try {
      final results = await Future.wait([
        widget.api.rankList(withSong: 3),
        _loadNewSongs(epoch: epoch),
      ]);
      // 等待期间用户已手动刷新（epoch 变化）：丢弃本响应，避免旧数据倒灌。
      if (!mounted || epoch != _loadEpoch) return;
      final ranks = results[0] as List<RankCategory>;
      final songs = results[1] as List<Song>;
      _cachedRanks = ranks;
      _persistRanks(ranks);
      if (!mounted) return;
      setState(() {
        _future = Future.value(ranks);
        _newSongsFuture = Future.value(songs);
      });
    } catch (_) {
      // 静默刷新失败，保持缓存数据不变
    } finally {
      _silentRefreshing = false;
    }
  }

  /// 对外入口：双击首页按钮时回到排行榜顶部并刷新（标题栏刷新按钮已移除）。
  Future<void> refresh() async {
    // 双击刷新优先级最高：使在途的静默刷新/冷启动恢复响应作废。
    final epoch = ++_loadEpoch;
    final rankFuture = _loadRanks(epoch: epoch);
    final songsFuture = _loadNewSongs(epoch: epoch);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final size = MediaQuery.sizeOf(context);
    final isCarLandscape =
        size.width > size.height && ThemeController.instance.carModeEnabled;

    // 磁盘恢复中（_future 尚未确定）：显示骨架，避免闪现空态。
    final initialFuture = _future;
    if (initialFuture == null) {
      return _RankSkeleton(isCarLandscape: isCarLandscape);
    }
    return FutureBuilder<List<RankCategory>>(
      future: initialFuture,
      builder: (context, snapshot) {
        // 与推荐页一致：优先显示内存/磁盘缓存，无缓存才走骨架/错误态；
        // 刷新失败时保持缓存显示，不闪回错误页。
        final ranks = snapshot.data ?? _cachedRanks ?? const <RankCategory>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            ranks.isEmpty) {
          return _RankSkeleton(isCarLandscape: isCarLandscape);
        }
        if (snapshot.hasError && ranks.isEmpty) {
          return _RankError(
            message: snapshot.error.toString(),
            onRetry: refresh,
          );
        }
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
              fallback: _cachedNewSongs ?? const <Song>[],
            ),
            // 榜单标题 + 刷新按钮：与电台 _RadioSectionTitle 视觉与间距完全对齐
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark ? .18 : .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.leaderboard_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '排行榜',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            // 与电台标题下 SizedBox(height: 12) 完全对齐。
            const SizedBox(height: 12),
            // 榜单列表 / 网格
            if (isCarLandscape)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 3.6,
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
              )
            else
              // 手机版双列小卡：一屏展示更多榜单，封面 + 榜名 + 前两首。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final count = constraints.maxWidth > 600 ? 3 : 2;
                    const spacing = 12.0;
                    const cardHeight = 148.0;
                    final cellWidth =
                        (constraints.maxWidth - spacing * (count - 1)) / count;
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: count,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: cellWidth / cardHeight,
                      ),
                      itemCount: ranks.length,
                      itemBuilder: (context, index) {
                        final rank = ranks[index];
                        return _RankGridCard(
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
    this.fallback = const <Song>[],
  });

  final Future<List<Song>>? future;
  final PlayerController player;
  final AuthController auth;
  final List<Song> fallback;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Song>>(
      future: future,
      builder: (context, snapshot) {
        final songs = snapshot.data ?? fallback;
        if (songs.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (songs.isEmpty) return const SizedBox.shrink();

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: isDark ? .18 : .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.fiber_new_rounded, size: 18, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '新歌推荐',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => player.playSong(songs.first, queue: songs),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('播放'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final showCount = songs.length > 10 ? 10 : songs.length;
                  // 桌面宽窗：横轨转网格（项宽 ~120、行高 142），不再横向滚动。
                  if (AdaptiveLayout.isDesktopGridWidth(constraints.maxWidth)) {
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: showCount,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 120,
                        mainAxisExtent: 142,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        // 正在播放徽标随播放状态实时变化：只重建单张卡片。
                        return AnimatedBuilder(
                          animation: player,
                          builder: (context, _) => _NewSongCard(
                            song: song,
                            onTap: () {
                              if (openPlayerIfSameSong(
                                context,
                                player: player,
                                auth: auth,
                                song: song,
                              )) {
                                return;
                              }
                              player.playSong(song, queue: songs);
                            },
                            isPlaying: player.currentSong?.hash == song.hash &&
                                song.hash.isNotEmpty,
                          ),
                        );
                      },
                    );
                  }
                  // 非桌面 / 窄窗：保持原横轨，仅接入滚轮横滚。
                  return SizedBox(
                    height: 142,
                    child: HorizontalWheelScroll(
                      builder: (context, controller) => ListView.separated(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        itemCount: showCount,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final song = songs[index];
                          return AnimatedBuilder(
                            animation: player,
                            builder: (context, _) => _NewSongCard(
                              song: song,
                              onTap: () {
                                if (openPlayerIfSameSong(
                                  context,
                                  player: player,
                                  auth: auth,
                                  song: song,
                                )) {
                                  return;
                                }
                                player.playSong(song, queue: songs);
                              },
                              isPlaying:
                                  player.currentSong?.hash == song.hash &&
                                      song.hash.isNotEmpty,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 108,
        decoration: BoxDecoration(
          color: isPlaying
              ? colorScheme.primary.withValues(alpha: isDark ? .14 : .07)
              : (isDark ? Colors.white.withValues(alpha: .06) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPlaying
                ? colorScheme.primary.withValues(alpha: .30)
                : (isDark ? Colors.white.withValues(alpha: .10) : Colors.white.withValues(alpha: .92)),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? .18 : .06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Artwork(url: song.coverUrl, size: 108, borderRadius: 0),
                ),
                if (isPlaying)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: .40),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.equalizer_rounded,
                        size: 14,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: isPlaying ? colorScheme.primary : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isPlaying
                          ? colorScheme.primary.withValues(alpha: .75)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 手机版双列榜单小卡：封面 + 榜名 + 首行歌曲 + 圆形进入钮。
class _RankGridCard extends StatelessWidget {
  const _RankGridCard({
    required this.rank,
    required this.onTap,
  });

  final RankCategory rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final first = rank.songs.isNotEmpty ? rank.songs.first : null;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: .06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: .10) : Colors.white.withValues(alpha: .92),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .18 : .06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(
                  height: 88,
                  width: double.infinity,
                  child: Artwork(
                    url: rank.imageUrl,
                    size: double.infinity,
                    borderRadius: 0,
                    icon: Icons.leaderboard_rounded,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            rank.rankName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            first == null
                                ? '查看完整榜单歌曲'
                                : (first.artist.isEmpty
                                    ? first.title
                                    : '${first.title} - ${first.artist}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: isDark ? .18 : .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colorScheme.primary,
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

class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank, required this.onTap});

  final RankCategory rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final isCarMode =
        size.width > size.height && ThemeController.instance.carModeEnabled;

    // 手机版做成更精致的白卡：加大封面、歌曲带序号+歌手、尾部主色小圆钮。
    final cardPadding = isCarMode ? 14.0 : 12.0;
    final artworkSize = isCarMode ? 88.0 : 76.0;
    final nameFontSize = isCarMode ? 17.0 : 16.0;
    final songFontSize = isCarMode ? 14.0 : 12.5;
    final spacing = isCarMode ? 16.0 : 12.0;
    final maxSongs = isCarMode ? 2 : 3;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: .06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: .10) : Colors.white.withValues(alpha: .92),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .18 : .06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Row(
              children: [
                // 封面（带轻阴影，与首页白卡一致）
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? .20 : .08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(
                      dimension: artworkSize,
                      child: Artwork(
                        url: rank.imageUrl,
                        size: artworkSize,
                        borderRadius: 12,
                        icon: Icons.leaderboard_rounded,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                // 榜单信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rank.rankName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: nameFontSize,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (rank.songs.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...rank.songs.take(maxSongs).toList().asMap().entries.map(
                              (entry) {
                                final i = entry.key;
                                final s = entry.value;
                                final subtitle = s.artist.isEmpty ? s.title : '${s.title} - ${s.artist}';
                                return Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        child: Text(
                                          '${i + 1}',
                                          style: TextStyle(
                                            fontSize: songFontSize,
                                            fontWeight: FontWeight.w900,
                                            fontStyle: FontStyle.italic,
                                            height: 1.2,
                                            color: i == 0
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant.withValues(alpha: .75),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: songFontSize,
                                            height: 1.25,
                                            fontWeight: FontWeight.w500,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ] else ...[
                        const SizedBox(height: 6),
                        Text(
                          '查看完整榜单歌曲',
                          style: TextStyle(
                            fontSize: songFontSize,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: .75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // 角标与箭头放在同一尾部行里垂直居中，天生对齐。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: isDark ? .18 : .10),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '榜单',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          letterSpacing: 0.2,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: isCarMode ? 40 : 34,
                      height: isCarMode ? 40 : 34,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: isDark ? .18 : .12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: isCarMode ? 24 : 20,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
  var _isLoadingAllSongs = false;
  var _allSongsLoaded = false;
  String? _error;
  String? _focusedSongKey;

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
    // 首屏加载中不触发加载更多，避免并发请求第 1 页导致重复数据
    if (_isLoading) return;
    if (!_scrollController.hasClients || !_hasMore || _isLoadingMore) return;
    if (_scrollController.position.extentAfter < 400) _loadMore();
  }

  Future<void> _loadMore() async {
    // 首屏加载中不触发加载更多，避免并发请求第 1 页导致重复数据
    if (_isLoading || _isLoadingMore || !_hasMore) return;
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
    if (openPlayerIfSameSong(
      context,
      player: widget.player,
      auth: widget.auth,
      song: song,
    )) {
      return;
    }
    widget.player.playSong(song, queue: List.of(_songs));
    _expandQueueInBackgroundIfNeeded(startedWith: song);
  }

  void _playAll() {
    if (_songs.isNotEmpty) {
      final first = _songs.first;
      widget.player.playSong(first, queue: List.of(_songs));
      _expandQueueInBackgroundIfNeeded(startedWith: first);
    }
  }

  /// 后台拉取榜单全部分页，并在仍播放本榜单时扩展播放队列（与歌单详情页同款机制）。
  /// 播放立即以已加载列表开始，不阻塞等待；补全完成后静默替换队列，
  /// 避免"播放全部只含首屏 50 首、播完回到第一首"。
  void _expandQueueInBackgroundIfNeeded({required Song startedWith}) {
    if (_allSongsLoaded || !_hasMore) return;
    final startedKey = startedWith.hash.isNotEmpty ? startedWith.hash : startedWith.id;
    if (startedKey.isEmpty) return;
    unawaited(() async {
      await _loadAllSongs();
      if (!mounted) return;
      final current = widget.player.currentSong;
      if (current == null) return;
      final currentKey = current.hash.isNotEmpty ? current.hash : current.id;
      final queueStillOurs = widget.player.queue.any((s) {
        final k = s.hash.isNotEmpty ? s.hash : s.id;
        return k == startedKey;
      });
      // 用户已切到其它来源则不改队列
      if (currentKey != startedKey && !queueStillOurs) return;
      final expanded = List<Song>.of(_songs);
      if (expanded.length <= widget.player.queue.length) return;
      await widget.player.replaceQueue(expanded);
    }());
  }

  Future<void> _loadAllSongs() async {
    if (_isLoadingAllSongs || _allSongsLoaded) return;
    setState(() => _isLoadingAllSongs = true);
    try {
      final allSongs = await widget.api.rankAudioAll(
        rankId: widget.rank.rankId,
      );
      if (!mounted) return;
      setState(() {
        // 增量追加：保留已加载歌曲，仅追加尚未加载的，避免列表滚动位置被重置
        final existingKeys = _songs.map(_songKey).toSet();
        for (final song in allSongs) {
          final key = _songKey(song);
          if (existingKeys.contains(key)) continue;
          _songs.add(song);
          existingKeys.add(key);
        }
        _hasMore = false;
        _allSongsLoaded = true;
        _isLoadingAllSongs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingAllSongs = false);
    }
  }

  String _songKey(Song song) =>
      song.hash.isNotEmpty ? song.hash : song.id;

  void _openArtist(Song song) {
    final artist = song.artists.firstWhere(
      (a) => a.name.isNotEmpty,
      orElse: () => ArtistRef(id: '', name: song.artist),
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

  void _showSongMenu(Song song, {Offset? anchor}) {
    showSongActionSheet(
      context: context,
      song: song,
      anchor: anchor,
      actions: [
        SongSheetAction(
          icon: Icons.queue_music_rounded,
          title: '下一首播放',
          onTap: () => addSongToQueueWithFeedback(
            context: context,
            player: widget.player,
            song: song,
          ),
        ),
        SongSheetAction(
          icon: Icons.playlist_add_rounded,
          title: '添加到歌单',
          onTap: () => showAddToPlaylistSheet(
            context: context,
            auth: widget.auth,
            song: song,
          ),
        ),
        SongSheetAction(
          icon: Icons.person_rounded,
          title: '查看歌手',
          onTap: () => _openArtist(song),
        ),
        if (widget.player.downloadController != null)
          SongSheetAction(
            icon: widget.player.downloadController!.isDownloaded(song)
                ? Icons.download_done_rounded
                : Icons.download_rounded,
            title: widget.player.downloadController!.isDownloaded(song)
                ? '已下载'
                : '下载',
            onTap: () => widget.player.downloadController!
                .download(song, widget.player.audioQuality),
          ),
      ],
    );
  }

  Widget _buildDesktopAppBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 200,
      surfaceTintColor: Colors.transparent,
      backgroundColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black.withValues(alpha: .08),
      title: AnimatedBuilder(
        animation: _scrollController,
        builder: (context, _) {
          var collapsed = false;
          if (_scrollController.hasClients) {
            final delta = 200.0 - kToolbarHeight;
            collapsed = delta <= 0 || _scrollController.offset > delta - 40;
          }
          return AnimatedOpacity(
            opacity: collapsed ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Text(
              widget.rank.rankName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        },
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: _buildDesktopHeroHeader(context),
      ),
    );
  }

  Widget _buildDesktopHeroHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final updateFreq = widget.rank.updateFrequency.isNotEmpty
        ? widget.rank.updateFrequency
        : '实时更新';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF1B2E49), Color(0xFF0D121E), Color(0xFF06070A)]
              : const [Color(0xFFD3E8FF), Color(0xFFEDF4FF), Color(0xFFFFFFFF)],
          stops: isDark ? const [0, 0.55, 1] : const [0, 0.62, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 4, 24, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? .35 : .18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Artwork(
                  url: widget.rank.imageUrl,
                  size: 120,
                  borderRadius: 16,
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.rank.rankName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(
                          alpha: isDark ? .20 : .10,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_songs.length} 首歌曲 · $updateFreq',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _playAll,
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('播放全部'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                            elevation: 0,
                          ),
                        ),
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
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

  Widget _buildMobileAppBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 220,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black.withValues(alpha: .08),
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
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    final friendly = friendlyServiceErrorMessage(_error ?? '加载失败');
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 44,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                '暂时连接不上音乐服务',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                friendly,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              if (isDesktopFormFactor)
                _buildDesktopAppBar(context)
              else
                _buildMobileAppBar(context),
              if (isDesktopFormFactor) ...[
                if (_error != null && _songs.isEmpty)
                  _buildErrorState(colorScheme)
                else ...[
                  if (_songs.isNotEmpty)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _RankTableStickyHeaderDelegate(
                        child: Container(
                          color: colorScheme.surface,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const DesktopSongTableHeader(
                            selecting: false,
                            allSelected: false,
                            onToggleSelectAll: null,
                          ),
                        ),
                      ),
                    ),
                  if (_songs.isEmpty && _isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      sliver: SliverFixedExtentList(
                        itemExtent: DesktopSongTableRow.rowHeight,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final song = _songs[index];
                            return DesktopSongTableRow(
                              song: song,
                              index: index + 1,
                              player: widget.player,
                              auth: widget.auth,
                              canDelete: false,
                              selecting: false,
                              selected: false,
                              isFocused: _focusedSongKey == _songKey(song),
                              onTap: () => setState(
                                () => _focusedSongKey = _songKey(song),
                              ),
                              onDoubleTap: () => _playSong(song),
                              onPlay: () => _playSong(song),
                              onAddToPlaylist: () => showAddToPlaylistSheet(
                                context: context,
                                auth: widget.auth,
                                song: song,
                              ),
                              onDelete: () {},
                              onViewArtist: () => _openArtist(song),
                              onMore: () => _showSongMenu(song),
                              onSecondaryMore: (position) =>
                                  _showSongMenu(song, anchor: position),
                            );
                          },
                          childCount: _songs.length,
                        ),
                      ),
                    ),
                    if (_isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ],
              ] else ...[
                // 播放全部按钮
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: .06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: .10)
                              : Colors.white.withValues(alpha: .92),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? .18 : .06,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: isDark ? .18 : .12,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_songs.length} 首歌曲',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _playAll,
                            icon:
                                const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('播放全部'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                              elevation: 0,
                            ),
                          ),
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.only(left: 12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 歌曲列表
                if (_error != null && _songs.isEmpty)
                  _buildErrorState(colorScheme)
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
                          api: widget.api,
                          auth: widget.auth,
                          player: widget.player,
                          queue: _songs,
                        );
                      },
                      childCount: _songs.length + (_hasMore ? 1 : 0),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 166)),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 10,
            child: MiniPlayer(player: widget.player, auth: widget.auth),
          ),
        ],
      ),
    );
  }
}

/// PC 桌面端表格吸顶代理。
class _RankTableStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _RankTableStickyHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 36.0;

  @override
  double get maxExtent => 36.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      child;

  @override
  bool shouldRebuild(covariant _RankTableStickyHeaderDelegate oldDelegate) =>
      child != oldDelegate.child;
}

// ---------------------------------------------------------------------------
// 排行榜歌曲行
// ---------------------------------------------------------------------------

class _RankSongRow extends StatelessWidget {
  const _RankSongRow({
    required this.index,
    required this.song,
    required this.onTap,
    required this.api,
    required this.auth,
    required this.player,
    required this.queue,
  });

  final int index;
  final Song song;
  final VoidCallback onTap;
  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final List<Song> queue;

  void _showActions(BuildContext context) {
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
          onTap: () {
            final artist = song.artists.firstWhere(
              (a) => a.name.isNotEmpty,
              orElse: () => const ArtistRef(id: '', name: ''),
            );
            if (artist.name.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArtistDetailPage(
                  api: api,
                  auth: auth,
                  artist: artist,
                  player: player,
                ),
              ),
            );
          },
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTop3 = index <= 3;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final isPlaying =
            song.hash.isNotEmpty && player.currentSong?.hash == song.hash;
        final isActive = isPlaying;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            decoration: BoxDecoration(
              color: isActive
                  ? colorScheme.primary.withValues(alpha: .08)
                  : (isDark ? Colors.white.withValues(alpha: .06) : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? colorScheme.primary.withValues(alpha: .18)
                    : (isDark ? Colors.white.withValues(alpha: .10) : Colors.white.withValues(alpha: .92)),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? .18 : .06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onTap,
                onLongPress: () => _showActions(context),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    children: [
                      // 排名
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isTop3
                              ? colorScheme.primary.withValues(alpha: isDark ? .18 : .12)
                              : (isDark ? Colors.white.withValues(alpha: .06) : colorScheme.surfaceContainerHighest.withValues(alpha: .9)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$index',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isTop3 ? 14 : 13,
                              fontWeight: isTop3 ? FontWeight.w900 : FontWeight.w700,
                              color: isTop3 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              fontStyle: isTop3 ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 封面
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Artwork(url: song.coverUrl, size: 48, borderRadius: 10),
                        ),
                      ),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isPlaying
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
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 播放中指示 / 更多操作按钮
                      if (isPlaying)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.equalizer_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                        )
                      else
                        IconButton(
                          tooltip: '更多',
                          onPressed: () => _showActions(context),
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: .6),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ),
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
  const _RankSkeleton({this.isCarLandscape = false});

  final bool isCarLandscape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(10),
    );

    Widget buildItem() => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(width: 72, height: 72, decoration: placeholder),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 14, decoration: placeholder),
                    const SizedBox(height: 8),
                    Container(
                        width: double.infinity,
                        height: 10,
                        decoration: placeholder),
                    const SizedBox(height: 6),
                    Container(width: 160, height: 10, decoration: placeholder),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget buildGridItem() => Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 88,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: placeholder,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 90, height: 13, decoration: placeholder),
                    const SizedBox(height: 7),
                    Container(
                        width: double.infinity,
                        height: 10,
                        decoration: placeholder),
                  ],
                ),
              ),
            ],
          ),
        );

    if (isCarLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 3.6,
              ),
              itemCount: 8,
              itemBuilder: (context, index) => buildItem(),
            );
          },
        ),
      );
    }

    // 手机版骨架与双列小卡同构。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth > 600 ? 3 : 2;
          const spacing = 12.0;
          const cardHeight = 148.0;
          final cellWidth =
              (constraints.maxWidth - spacing * (count - 1)) / count;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: cellWidth / cardHeight,
            ),
            itemCount: 6,
            itemBuilder: (context, index) => buildGridItem(),
          );
        },
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
    // 与电台 _ErrorView 统一视觉：不再忽略 message，而是转成友好文案，
    // 避免无网络时只显示干巴巴的“加载失败”或透出原始异常。
    final friendly = friendlyServiceErrorMessage(message);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 44,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '暂时连接不上音乐服务',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              friendly,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
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
