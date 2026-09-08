import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../widgets/app_feedback.dart' show friendlyServiceErrorMessage;
import '../widgets/app_section.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/app_version.dart';
import '../../models/music_models.dart';
import '../../services/app_update_service.dart';
import '../../services/cache_service.dart';
import '../../services/music_api.dart';
import '../adaptive_layout.dart';
import '../form_factor.dart';
import '../widgets/app_update_widgets.dart';
import '../widgets/artwork.dart';
import '../widgets/cover_play_overlay.dart';
import '../widgets/home_collapsible_header.dart';
import '../widgets/home_song_row.dart';
import '../widgets/horizontal_wheel_scroll.dart';
import '../widgets/refresh_equalizer.dart';
import '../widgets/swr_section_state.dart';
import '../widgets/toast.dart';
import '../player/song_tap_handler.dart';
import 'artist_detail_page.dart';
import 'playlist_detail_page.dart';
import '../../controllers/theme_controller.dart';
import '../../controllers/download_controller.dart';
import '../../controllers/local_music_controller.dart';
import 'playback_history_page.dart';
import 'rank_page.dart';
import 'recommended_playlists_page.dart';
import 'settings_page.dart';
import 'top_songs_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.cache,
    required this.theme,
    required this.downloads,
    required this.localMusic,
    this.sectionIndex = 0,
    this.onTabSwitch,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final CacheService cache;
  final ThemeController theme;
  final DownloadController downloads;
  final LocalMusicController localMusic;
  final int sectionIndex;
  final ValueChanged<int>? onTabSwitch;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends SwrSectionState<HomePage, HomeData>
    with TickerProviderStateMixin {
  static HomeData? _cachedData;
  static bool _hasAutoPlayed = false;

  final ScrollController _scrollController = ScrollController();
  // 非车机三 tab 内容列表各自的滚动控制器。顶栏（搜索栏 + 标签栏）是
  // 页面层固定组件（Stack 覆盖在 PageView 之上，见 build）：横向切页时
  // 顶栏纹丝不动，只有内容区随页面切换；顶栏收折进度由各 tab 的内容
  // 滚动 offset 派生（见 _updateHeaderShrink），不再需要 NestedScrollView
  // 外层 offset 镜像。
  final List<ScrollController> _tabControllers = List.generate(
    3,
    (_) => ScrollController(),
  );
  // 顶栏收折进度（0 = 完全展开，_headerCollapseRange = 完全收折）：
  // 只驱动顶栏自身的重绘，切页/滚动都不触发整页 setState。
  final ValueNotifier<double> _headerShrink = ValueNotifier<double>(0.0);
  // 头部区间同步中的重入保护：把某个 tab 的头部进度镜像到其它 tab 时
  // 会触发它们的 listener 回调，用此标志避免递归同步。
  bool _syncingHeaderOffsets = false;

  /// 顶栏完全收折所需的滚动距离：等于 delegate 默认参数下
  /// maxExtent - minExtent（topMargin 8 + searchBarHeight 36 + spacing 8）。
  /// 若调整 HomeCollapsibleHeaderDelegate 的默认尺寸需同步更新。
  static const double _headerCollapseRange = 52.0;
  // 排行榜 / 电台的刷新入口：双击首页按钮时调用（标题栏刷新按钮已移除）。
  final GlobalKey<RankPageState> _rankKey = GlobalKey<RankPageState>();
  final GlobalKey<_RadioSectionState> _radioKey =
      GlobalKey<_RadioSectionState>();

  late final AppUpdateService _updateService;
  AppVersionInfo? _availableUpdate;
  var _sectionIndex = 0;
  var _updateBannerDismissed = false;
  var _autoUpdateDialogShown = false;
  late PageController _pageController;
  // 车机/竖屏形态切换记忆：车机模式下 PageView 离树，PageController 会丢失
  // 当前页（重建时回退到 initialPage=0 即推荐页）。记录上帧形态，
  // 车机切回竖屏时用 _sectionIndex 重建控制器，保证回到对应 tab。
  bool? _lastIsCarMode;

  @override
  void initState() {
    super.initState();
    _sectionIndex = widget.sectionIndex;
    _pageController = PageController(initialPage: _sectionIndex);
    _pageController.addListener(_updateHeaderShrink);
    for (final controller in _tabControllers) {
      controller.addListener(_updateHeaderShrink);
    }
    _updateService = AppUpdateService();
    widget.auth.addListener(_handleAuthChanged);
    if (AppUpdateService.isSupportedPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectionIndex != widget.sectionIndex) {
      // 外部切换 tab（如侧栏/底部导航）：同样先对齐目标页头部，保持
      // 顶栏三 tab 统一行动主体。
      _alignTabToShrink(
        widget.sectionIndex,
        _headerShrink.value.clamp(0.0, _headerCollapseRange),
      );
      _sectionIndex = widget.sectionIndex;
      if (_pageController.hasClients &&
          _pageController.page?.round() != widget.sectionIndex) {
        _pageController.animateToPage(
          widget.sectionIndex,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    for (final controller in _tabControllers) {
      controller.dispose();
    }
    _headerShrink.dispose();
    widget.auth.removeListener(_handleAuthChanged);
    super.dispose();
  }

  /// 车机/竖屏形态切换时同步 PageView 到 [_sectionIndex]。
  ///
  /// 根因：竖屏三 tab 靠 PageView + PageController 承载，车机模式下
  /// PageView 离树（改用单 CustomScrollView + _PersistentTabPane），
  /// controller 失活；切回竖屏时新 PageView 会用创建时的 initialPage
  ///（多为 0=推荐）重建，而不是当前 [_sectionIndex]（如 1=排行榜），
  /// 于是从排行榜进车机再缩回会闪回推荐页。
  /// 此处在车机→竖屏的首帧同步重建控制器（无闪烁），已挂载的极端
  /// 情况降级为 post-frame jumpToPage。
  void _syncPageControllerForMode(bool isCarMode) {
    if (_lastIsCarMode == null) {
      _lastIsCarMode = isCarMode;
      return;
    }
    if (_lastIsCarMode == isCarMode) return;
    final wasCarMode = _lastIsCarMode!;
    _lastIsCarMode = isCarMode;
    // 仅处理车机→竖屏：竖屏→车机时 PageView 即将离树，无需动 controller。
    if (!wasCarMode || isCarMode) return;
    if (!_pageController.hasClients &&
        _pageController.initialPage != _sectionIndex) {
      // 首帧同步重建：新 PageView 直接落在对应 tab，无“推荐闪一下”；
      // 旧 controller 无挂载，dispose 安全。
      _pageController.dispose();
      _pageController = PageController(initialPage: _sectionIndex);
      _pageController.addListener(_updateHeaderShrink);
      return;
    }
    final target = _sectionIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients &&
          _pageController.page?.round() != target) {
        _pageController.jumpToPage(target);
      }
    });
  }

  /// 由三 tab 内容滚动位置推导顶栏收折进度。
  ///
  /// 顶栏是页面层固定组件，不再随 PageView 横向平移，是三个 tab 共用的
  /// 同一个行动主体：收折态全局统一，切页不重置——推荐页下滑收起搜索框
  /// 后切到排行榜/电台时搜索框保持收起，反之任一页上滑展开后其它页也
  /// 同步展开，不再出现“一个有搜索框、一个没有”的跳变。
  ///
  /// 规则：
  /// - 静止时任一 tab 在头部区间（0.._headerCollapseRange）内滚动，
  ///   把其它同样处于头部区间的 tab 镜像到同一进度；深滚（超出头部
  ///   区间）的 tab 保留各自内容进度不动。
  /// - 切页动画中只把目标页的头部对齐到源页，不动源页（源页可见，
  ///   动它会纵跳；目标页在屏外，对齐不可见、无抖动），使过渡期间
  ///   顶栏高度保持稳定。
  /// 任一 tab 滚动或 PageView 翻页都会触发本函数（listener），只更新
  /// ValueNotifier，不 setState（镜像 jumpTo 期间用 [_syncingHeaderOffsets]
  /// 防重入）。
  void _updateHeaderShrink() {
    if (!mounted || _syncingHeaderOffsets) return;
    var page = _sectionIndex.toDouble();
    if (_pageController.hasClients &&
        _pageController.position.haveDimensions) {
      page = (_pageController.page ?? page).clamp(0.0, 2.0);
    }
    final i = page.floor().clamp(0, 2);
    final j = (i + 1).clamp(0, 2);
    final t = (page - i).clamp(0.0, 1.0);
    double offsetOf(int index) {
      final controller = _tabControllers[index];
      return controller.hasClients ? controller.offset : 0.0;
    }

    final offset = offsetOf(i) + (offsetOf(j) - offsetOf(i)) * t;
    final shrink = offset.clamp(0.0, _headerCollapseRange);
    if ((_headerShrink.value - shrink).abs() > 0.1) {
      _headerShrink.value = shrink;
    }

    final settled = (page - page.round()).abs() < 0.02;
    if (!settled) {
      // 切页动画中：目标页头部向源页对齐（源页不动）。
      final src = _sectionIndex.clamp(0, 2);
      final dst = (i == src) ? j : i;
      if (dst != src) {
        _alignTabToShrink(dst, offsetOf(src).clamp(0.0, _headerCollapseRange));
      }
      return;
    }
    // 静止时：头部区间内的列表互相镜像，深滚列表不动。
    _syncingHeaderOffsets = true;
    try {
      for (final controller in _tabControllers) {
        if (!controller.hasClients) continue;
        if (controller.offset <= _headerCollapseRange + 0.5) {
          final target = shrink.clamp(
            controller.position.minScrollExtent,
            controller.position.maxScrollExtent,
          );
          if ((controller.offset - target).abs() > 0.5) {
            try {
              controller.jumpTo(target);
            } catch (_) {
              // 滚动中或布局未就绪时忽略，下次滚动/切页会再次对齐。
            }
          }
        }
      }
    } finally {
      _syncingHeaderOffsets = false;
    }
  }

  /// 把目标 tab 的头部进度至少推高到 [shrink]（深滚不动）。
  ///
  /// 用于切页前/切页后对齐：目标还在头部区间顶部（如 offset 0）而顶栏
  /// 已收起时，把它推到与顶栏一致的位置，避免切页后搜索框突然冒出来。
  void _alignTabToShrink(int index, double shrink) {
    if (index < 0 || index >= _tabControllers.length) return;
    final controller = _tabControllers[index];
    if (!controller.hasClients) return;
    if (controller.offset > _headerCollapseRange + 0.5) return;
    if (controller.offset >= shrink - 0.5) return;
    final target = shrink.clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if ((controller.offset - target).abs() <= 0.5) return;
    _syncingHeaderOffsets = true;
    try {
      controller.jumpTo(target);
    } catch (_) {
      // 滚动中或布局未就绪时忽略，动画中的后续帧会继续对齐。
    } finally {
      _syncingHeaderOffsets = false;
    }
  }

  /// 当前子 tab 对应的刷新入口：双击首页与桌面头部刷新按钮共用同一语义。
  Future<void> _refreshCurrentSection() => switch (_sectionIndex) {
        1 => _rankKey.currentState?.refresh() ?? Future<void>.value(),
        2 => _radioKey.currentState?.refresh() ?? Future<void>.value(),
        _ => refresh(),
      };

  /// 判定滚动的阈值（px）：超过即认为用户已在本页下滑。
  static const double _tapRefreshScrollThreshold = 8.0;

  /// 顶部胶囊 tab 点击：点到其它 tab 只切换（各 tab 内容状态靠 KeepAlive
  /// 保留，不刷新）；点中当前 tab 则无条件回顶刷新（含顶部均衡器动画）。
  void _handleSectionTap(int value, {required bool animatePage}) {
    if (value == _sectionIndex) {
      unawaited(scrollToTopAndRefresh());
      return;
    }
    // 切页前先把目标页头部对齐到当前顶栏收折态：顶栏是三 tab 共用的
    // 同一个行动主体，收起/展开切页不重置。深滚的目标页不动。
    _alignTabToShrink(
      value,
      _headerShrink.value.clamp(0.0, _headerCollapseRange),
    );
    setState(() => _sectionIndex = value);
    widget.onTabSwitch?.call(value + 1);
    if (animatePage && _pageController.hasClients) {
      _pageController.animateToPage(
        value,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 双击底部首页按钮：回到当前 tab 顶部并且刷新对应内容。
  /// 推荐 tab 刷新推荐流，排行榜 / 电台 tab 刷新各自内容（标题栏刷新按钮已移除，
  /// 统一收敛到这里）。车机顶栏点中当前 tab 同样走这里（含均衡器动画）。
  Future<void> scrollToTopAndRefresh() async {
    final size = MediaQuery.sizeOf(context);
    final isCarMode =
        size.width > size.height && ThemeController.instance.carModeEnabled;
    if (isCarMode) {
      // 车机单滚动容器：直接回顶。
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      // 内容回顶；顶栏收折进度由内容 offset 派生，随动画自动展开。
      final controller = _tabControllers[_sectionIndex];
      if (controller.hasClients) {
        try {
          await controller.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        } catch (_) {
          // 滚动中页面已销毁时忽略。
        }
      }
    }
    if (!mounted) return;
    await _refreshCurrentSection();
  }

  /// 车机模式是否已滚动（单滚动容器偏离顶部即算）。
  /// 供车机顶栏点中当前 tab 时判断，未滚动则什么都不做。
  bool get isCarScrolled {
    if (!mounted) return false;
    return _scrollController.hasClients &&
        _scrollController.offset > _tapRefreshScrollThreshold;
  }

  void _handleAuthChanged() {
    if (widget.auth.isRestoring || !widget.auth.isLoggedIn) {
      return;
    }
    // 首次加载（无缓存）或 auth 恢复完成后触发加载（已有数据则基类忽略）。
    loadIfNeverLoaded();
  }

  void _checkAndAutoPlay(HomeData data) {
    if (!widget.player.autoPlayOnStartupEnabled || _hasAutoPlayed) return;
    _hasAutoPlayed = true;

    final hasRestored = widget.player.hasRestoredPlaybackState;
    final songs = data.daily.songs;
    if (!hasRestored && songs.isEmpty) return;

    // 必须推迟到首帧构建完成后执行：_checkAndAutoPlay 会在 initState
    // 阶段被同步调用，此时直接调用 playSong 会触发 notifyListeners()，
    // 违反 Flutter "build 阶段不能触发 setState/notifyListeners" 规则。
    // 叠加 Windows 平台 just_audio 的 WinRT MediaPlayer COM 线程在应用
    // 启动早期尚未完全就绪，立即 setUrl()/play() 会与 UI 渲染竞争，
    // 导致 "Lost connection to device" 进程崩溃。
    // Windows 上额外延迟 300ms 让 native 层完全稳定后再启动播放。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final delay = defaultTargetPlatform == TargetPlatform.windows
          ? const Duration(milliseconds: 300)
          : Duration.zero;
      Future<void>.delayed(delay, () {
        if (!mounted) return;
        if (hasRestored) {
          widget.player.resumePlayback();
        } else {
          widget.player.playSong(songs.first, queue: songs);
        }
      });
    });
  }

  /// 新歌速递失败时返回空列表，不阻塞首页其他板块。
  Future<List<Song>> _loadTopSongsSafe() async {
    try {
      return await widget.api.topSongs();
    } catch (_) {
      return const [];
    }
  }

  // ---------------- SWR 数据钩子（骨架见 SwrSectionState） ----------------

  @override
  CacheService get cache => widget.cache;

  @override
  HomeData? get cachedData => _cachedData;

  @override
  set cachedData(HomeData? value) => _cachedData = value;

  @override
  String get cacheKey => 'cache_home';

  @override
  Duration get cacheTtl => AppConfig.homeCacheTtl;

  @override
  HomeData decodeCache(Map<String, dynamic> json) {
    return HomeData(
      daily: DailyRecommend.fromCache(json['daily'] as Map<String, dynamic>),
      playlists: (json['playlists'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlaylistSummary.fromCache)
          .toList(),
      topSongs: (json['topSongs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromCache)
          .where((song) => song.hash.isNotEmpty)
          .toList(),
    );
  }

  @override
  Map<String, dynamic> encodeCache(HomeData data) => {
        'daily': data.daily.toCache(),
        'playlists': data.playlists.map((p) => p.toCache()).toList(),
        'topSongs': data.topSongs.map((song) => song.toCache()).toList(),
      };

  /// 三个板块是否至少有一个非空：全空说明多半是接口异常的静默空数据，
  /// 不应写入/覆盖内存与磁盘缓存。
  @override
  bool hasContent(HomeData data) =>
      data.daily.songs.isNotEmpty ||
      data.playlists.isNotEmpty ||
      data.topSongs.isNotEmpty;

  @override
  Future<HomeData> fetchData() async {
    final results = await Future.wait([
      widget.api.dailyRecommend(),
      widget.api.recommendedPlaylists(),
      _loadTopSongsSafe(),
    ]);
    return HomeData(
      daily: results[0] as DailyRecommend,
      playlists: results[1] as List<PlaylistSummary>,
      topSongs: results[2] as List<Song>,
    );
  }

  @override
  void onDataArrived(HomeData data) => _checkAndAutoPlay(data);

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

  Future<void> _playPlaylist(PlaylistSummary playlist) async {
    try {
      final fullCacheKey = 'playlist_full_${playlist.id}';
      final cached = await widget.cache.read<Map<String, dynamic>>(
        fullCacheKey,
        decode: (j) => j,
        ttl: AppConfig.playlistDetailTtl,
      );
      List<Song> songs = const [];
      if (cached != null && cached.data['songs'] is List) {
        songs = (cached.data['songs'] as List)
            .whereType<Map<String, dynamic>>()
            .map(Song.fromCache)
            .where((s) => s.hash.isNotEmpty)
            .toList();
      }
      if (songs.isEmpty) {
        Toast.info('正在获取歌单曲目…');
        songs = await widget.api.playlistSongs(
          playlist.id,
          page: 1,
          pageSize: 60,
        );
      }
      if (!mounted) return;
      if (songs.isNotEmpty) {
        widget.player.playSong(songs.first, queue: List<Song>.of(songs));
        Toast.show('正在播放歌单：${playlist.title}', type: ToastType.success);
      } else {
        Toast.error('歌单暂无可播放曲目');
      }
    } catch (_) {
      if (mounted) {
        Toast.error('播放失败，请稍后重试');
      }
    }
  }

  void _openDailyRecommend(DailyRecommend daily) {
    final playlist = PlaylistSummary(
      id: 'daily_recommend',
      title: '猜你喜欢',
      subtitle: daily.subtitle ?? '根据你的听歌偏好，每日精心推荐',
      coverUrl: daily.coverUrl ??
          (daily.songs.isNotEmpty ? daily.songs.first.coverUrl : null),
      songCount: daily.songs.length,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          playlist: playlist,
          initialSongs: daily.songs,
        ),
      ),
    );
  }

  void _openRecommendedPlaylists(List<PlaylistSummary> playlists) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecommendedPlaylistsPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          initialPlaylists: playlists,
        ),
      ),
    );
  }

  void _openTopSongs(List<Song> songs) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopSongsPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          initialSongs: songs,
        ),
      ),
    );
  }

  void _playSong(Song song, List<Song> queue) {
    // 点到当前歌：打开播放页，绝不重头播放（主流移动端一致行为）。
    if (openPlayerIfSameSong(
      context,
      player: widget.player,
      auth: widget.auth,
      song: song,
    )) {
      return;
    }
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

  // ignore: unused_element
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          theme: widget.theme,
          downloads: widget.downloads,
          cache: widget.cache,
          localMusic: widget.localMusic,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeData>(
      future: sectionFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _cachedData;
        // 桌面端：无下拉刷新手势（PC 无此惯例），滚动物理用桌面常规；
        // 数据重载入口改为页头刷新按钮（复用 refresh 同一逻辑）。
        // 移动端：RefreshIndicator + AlwaysScrollable 原样。
        // 车机端：无 RefreshIndicator 小圆圈，刷新统一走顶栏点中当前 tab，
        // 反馈与移动端一致用顶部均衡器动画（RefreshEqualizer）。
        final isDesktop = isDesktopFormFactor;
        final size = MediaQuery.sizeOf(context);
        final topPadding = MediaQuery.paddingOf(context).top;
        final isLandscape = size.width > size.height;
        final isCarMode = isLandscape && ThemeController.instance.carModeEnabled;
        // 车机↔竖屏切换时把 PageView 对齐到当前子 tab，避免缩回时掉回推荐页。
        _syncPageControllerForMode(isCarMode);

        Widget content;
        if (data == null) {
          if (snapshot.hasError) {
            content = CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorView(
                    message: snapshot.error.toString(),
                    onRetry: refresh,
                  ),
                ),
              ],
            );
          } else {
            content = CustomScrollView(
              controller: _scrollController,
              slivers: const [SliverToBoxAdapter(child: _HomeSkeleton())],
            );
          }
        } else if (!isCarMode) {
          // 顶栏（搜索栏 + 标签栏）是页面层固定组件：Stack 覆盖在 PageView
          // 之上，横向切页时顶栏纹丝不动，只有下方内容区随页面切换。
          // 各 tab 内容列表顶部留白 headerMaxExtent，滚动时内容从顶栏底下
          // 穿过；顶栏收折进度由当前 tab 的内容 offset 派生（切页动画中按
          // 页面位置在相邻 tab 间插值，见 _updateHeaderShrink）。
          final tabPhysics = isDesktop
              ? const ClampingScrollPhysics()
              : const AlwaysScrollableScrollPhysics();
          final headerDelegate = HomeCollapsibleHeaderDelegate(
            api: widget.api,
            auth: widget.auth,
            player: widget.player,
            sectionIndex: _sectionIndex,
            // 胶囊指示器直接监听 PageController：滑动过程中只重建头部内
            // 的小胶囊条，不再每像素 setState 整棵首页子树。
            pageTracker: _pageController,
            vsync: this,
            onSectionChanged: (value) {
              if (value == -1) {
                widget.onTabSwitch?.call(0);
              } else {
                _handleSectionTap(value, animatePage: true);
              }
            },
            onRefresh: isDesktop ? _refreshCurrentSection : null,
            topPadding: topPadding,
          );
          final headerMaxExtent = headerDelegate.maxExtent;

          Widget tabScrollView({
            required ScrollController controller,
            required PageStorageKey<String> bodyKey,
            required List<Widget> slivers,
          }) {
            return NotificationListener<ScrollEndNotification>(
              onNotification: (notification) {
                // 收折吸附：松手时收折到一半则动画到最近端点，对齐旧
                // SliverPersistentHeader floating + snap 的手感。
                if (controller.hasClients) {
                  final offset = controller.offset;
                  if (offset > 0 && offset < _headerCollapseRange) {
                    final target = offset < _headerCollapseRange / 2
                        ? 0.0
                        : _headerCollapseRange;
                    unawaited(
                      controller.animateTo(
                        target,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                      ),
                    );
                  }
                }
                return false;
              },
              child: CustomScrollView(
                key: bodyKey,
                controller: controller,
                physics: tabPhysics,
                slivers: [
                  // 顶部留白 = 顶栏完全展开的高度：内容从顶栏底下穿过。
                  SliverPadding(
                    padding: EdgeInsets.only(top: headerMaxExtent),
                  ),
                  if (_availableUpdate != null && !_updateBannerDismissed)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: AppUpdateBanner(
                          version: _availableUpdate!,
                          onTap: _showUpdateDetails,
                          onClose: () =>
                              setState(() => _updateBannerDismissed = true),
                        ),
                      ),
                    ),
                  ...slivers,
                ],
              ),
            );
          }

          content = Stack(
            children: [
              PageView(
                key: const Key('home_tabs_page_view'),
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _sectionIndex = index;
                  });
                  widget.onTabSwitch?.call(index + 1);
                  // 手势滑动切页：动画首帧已在 _updateHeaderShrink 里把目标页
                  // 向源页对齐，这里再补一次 post-frame 对齐，兜底懒加载
                  // 刚挂载（首帧 hasClients 为 false）的目标页。
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _alignTabToShrink(
                      index,
                      _headerShrink.value.clamp(0.0, _headerCollapseRange),
                    );
                  });
                },
                children: [
              // Tab 0: 推荐
              _HomeTabKeepAlive(
                child: tabScrollView(
                  controller: _tabControllers[0],
                  bodyKey:
                      const PageStorageKey<String>('home_tab_recommend'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: RefreshEqualizer(
                        visible: showRefreshEqualizer,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(18, 12, 18, 16),
                        child: _FeatureShelf(
                          daily: data.daily,
                          onDailyPlay: () {
                            final songs = data.daily.songs;
                            if (songs.isNotEmpty) {
                              widget.player.playSong(
                                songs.first,
                                queue: songs,
                              );
                            }
                          },
                          onDailyTap: () =>
                              _openDailyRecommend(data.daily),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SongSection(
                        key: ValueKey('song_section_$railResetEpoch'),
                        title: '大家都在听',
                        songs: data.daily.songs,
                        onPlay: _playSong,
                        isLiked: (song) => widget.auth.isLiked(song),
                        onLikeTap: (song) =>
                            widget.auth.toggleLike(song),
                        auth: widget.auth,
                        player: widget.player,
                        onViewArtist: _openArtist,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _PlaylistRail(
                        key: ValueKey('playlist_rail_$railResetEpoch'),
                        playlists: data.playlists,
                        onTap: _openPlaylist,
                        onPlay: _playPlaylist,
                        onTapTitle: () =>
                            _openRecommendedPlaylists(data.playlists),
                      ),
                    ),
                    if (data.topSongs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _TopSongRail(
                          key: ValueKey('topsong_rail_$railResetEpoch'),
                          songs: data.topSongs,
                          onPlay: (song) =>
                              _playSong(song, data.topSongs),
                          onTapTitle: () =>
                              _openTopSongs(data.topSongs),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: isDesktop ? 24 : 166),
                    ),
                  ],
                ),
              ),
              // Tab 1: 排行榜
              _HomeTabKeepAlive(
                child: tabScrollView(
                  controller: _tabControllers[1],
                  bodyKey: const PageStorageKey<String>('home_tab_rank'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: RankPage(
                        key: _rankKey,
                        api: widget.api,
                        auth: widget.auth,
                        player: widget.player,
                        cache: widget.cache,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: isDesktop ? 24 : 166),
                    ),
                  ],
                ),
              ),
              // Tab 2: 电台
              _HomeTabKeepAlive(
                child: tabScrollView(
                  controller: _tabControllers[2],
                  bodyKey: const PageStorageKey<String>('home_tab_radio'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _RadioSection(
                        key: _radioKey,
                        api: widget.api,
                        player: widget.player,
                        cache: widget.cache,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: isDesktop ? 24 : 166),
                    ),
                  ],
                ),
              ),
                ],
              ),
              // 页面层固定顶栏：覆盖在 PageView 之上，横向切页时固定不动；
              // 收折进度由 _headerShrink 驱动（当前 tab 内容 offset 派生）。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _headerShrink,
                  builder: (context, shrink, _) =>
                      HomeCollapsibleHeaderView(
                        delegate: headerDelegate,
                        shrinkOffset: shrink,
                      ),
                ),
              ),
            ],
          );
        } else {
          // 车机模式：保留原有车机定制滚动与卡片布局
          content = CustomScrollView(
            controller: _scrollController,
            physics: isDesktop
                ? const ClampingScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 均衡器置顶（与移动端各 tab 首个 sliver 对齐）：推荐/排行/电台
              // 刷新时都在内容最顶部展示。之前它藏在推荐 pane 内，被头部大卡
              // （猜你喜欢 + 统计 pills）顶到首屏之外，看起来像推荐页没有刷新。
              // 这里只响应首页自身的刷新（推荐）；排行/电台刷新时本标志为 false，
              // 各自 pane 内的均衡器负责展示，不会重复。
              SliverToBoxAdapter(
                child: RefreshEqualizer(
                  visible: showRefreshEqualizer,
                ),
              ),
              SliverToBoxAdapter(
                child: _RecommendHeader(
                  auth: widget.auth,
                  daily: data.daily,
                  sectionIndex: _sectionIndex,
                  onSectionChanged: (value) {
                    if (value == -1) {
                      widget.onTabSwitch?.call(0); // Switch to My tab
                    } else {
                      _handleSectionTap(value, animatePage: false);
                    }
                  },
                  onDailyPlay: () {
                    final songs = data.daily.songs;
                    if (songs.isNotEmpty) {
                      widget.player.playSong(songs.first, queue: songs);
                    }
                  },
                  onDailyTap: () => _openDailyRecommend(data.daily),
                  api: widget.api,
                  player: widget.player,
                  updateVersion:
                      _updateBannerDismissed ? null : _availableUpdate,
                  onUpdateTap: _showUpdateDetails,
                  onUpdateClose: () {
                    setState(() => _updateBannerDismissed = true);
                  },
                  onRefresh: isDesktop ? refresh : null,
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
                            key: ValueKey('car_song_section_$railResetEpoch'),
                            title: '大家都在听',
                            songs: data.daily.songs,
                            onPlay: _playSong,
                            isLiked: (song) => widget.auth.isLiked(song),
                            onLikeTap: (song) => widget.auth.toggleLike(song),
                            auth: widget.auth,
                            player: widget.player,
                            onViewArtist: _openArtist,
                          ),
                          _PlaylistRail(
                            key: ValueKey('car_playlist_rail_$railResetEpoch'),
                            playlists: data.playlists,
                            onTap: _openPlaylist,
                            onPlay: _playPlaylist,
                            onTapTitle: () =>
                                _openRecommendedPlaylists(data.playlists),
                          ),
                          if (data.topSongs.isNotEmpty)
                            _TopSongRail(
                              key: ValueKey('car_topsong_rail_$railResetEpoch'),
                              songs: data.topSongs,
                              onPlay: (song) =>
                                  _playSong(song, data.topSongs),
                              onTapTitle: () =>
                                  _openTopSongs(data.topSongs),
                            ),
                        ],
                      ),
                    ),
                    _PersistentTabPane(
                      visible: _sectionIndex == 1,
                      child: RankPage(
                        key: _rankKey,
                        api: widget.api,
                        auth: widget.auth,
                        player: widget.player,
                        cache: widget.cache,
                      ),
                    ),
                    _PersistentTabPane(
                      visible: _sectionIndex == 2,
                      child: _RadioSection(
                        key: _radioKey,
                        api: widget.api,
                        player: widget.player,
                        cache: widget.cache,
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: isDesktopFormFactor ? 24 : 166),
              ),
            ],
          );
        }

        final safeContent = ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: content,
        );

        // 桌面/车机均无 Material 小圆圈：桌面走页头刷新按钮，
        // 车机走顶栏点中当前 tab，两者反馈都用顶部均衡器动画。
        return isDesktop || isCarMode
            ? safeContent
            : RefreshIndicator(onRefresh: refresh, child: safeContent);
      },
    );
  }
}

class _HomeTabKeepAlive extends StatefulWidget {
  const _HomeTabKeepAlive({required this.child});
  final Widget child;

  @override
  State<_HomeTabKeepAlive> createState() => _HomeTabKeepAliveState();
}

class _HomeTabKeepAliveState extends State<_HomeTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _RecommendHeader extends StatelessWidget {
  const _RecommendHeader({
    required this.auth,
    required this.daily,
    required this.sectionIndex,
    required this.onSectionChanged,
    required this.onDailyPlay,
    required this.onDailyTap,
    required this.api,
    required this.player,
    required this.updateVersion,
    required this.onUpdateTap,
    required this.onUpdateClose,
    this.onRefresh,
  });

  final AuthController auth;
  final DailyRecommend daily;
  final int sectionIndex;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onDailyPlay;
  final VoidCallback onDailyTap;
  final MusicApi api;
  final PlayerController player;
  final AppVersionInfo? updateVersion;
  final VoidCallback onUpdateTap;
  final VoidCallback onUpdateClose;

  /// 桌面端下拉刷新的替代入口（页头刷新按钮）；移动端 / 车机端不传。
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    // 车机模式专属样式仅在开启时生效，普通横屏不受影响。
    final isCarMode = isLandscape && ThemeController.instance.carModeEnabled;
    // 车机宽屏：三个快捷入口在卡片右侧；车机非宽屏：入口在卡片下方。
    final isUltraWide =
        isCarMode &&
        size.width >= 1150 &&
        size.height >= 600 &&
        (size.width / size.height) > 2.0;

    // 清新淡雅：与我的页面一致，无大面积渐变，靠白卡与留白区分层次
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, isCarMode ? 4 : 10, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (updateVersion != null) ...[
                const SizedBox(height: 10),
                AppUpdateBanner(
                  version: updateVersion!,
                  onTap: onUpdateTap,
                  onClose: onUpdateClose,
                ),
              ],
              if (sectionIndex == 0) ...[
                const SizedBox(height: 14),
                if (isUltraWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _FeatureShelf(
                          daily: daily,
                          onDailyPlay: onDailyPlay,
                          onDailyTap: onDailyTap,
                        ),
                      ),
                      // 猜你喜欢与统计 pills 之间留出明确呼吸间距，
                      // 避免五张卡挤成一排的局促感。
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _CarQuickStatsPills(
                          auth: auth,
                          player: player,
                          onSwitchToMyTab: () => onSectionChanged(-1),
                          api: api,
                          isSideBySide: true,
                        ),
                      ),
                    ],
                  )
                else ...[
                  _FeatureShelf(
                    daily: daily,
                    onDailyPlay: onDailyPlay,
                    onDailyTap: onDailyTap,
                  ),
                  if (isCarMode)
                    _CarQuickStatsPills(
                      auth: auth,
                      player: player,
                      onSwitchToMyTab: () => onSectionChanged(-1),
                      api: api,
                    ),
                ],
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


/// 推荐区特性卡：新碟上架下线后只剩「猜你喜欢」一张，全宽独占一行。
/// 手机/车机/宽窄屏统一为单卡，不再需要双卡并排与窄屏竖排逻辑。
class _FeatureShelf extends StatelessWidget {
  const _FeatureShelf({
    required this.daily,
    required this.onDailyPlay,
    required this.onDailyTap,
  });

  final DailyRecommend daily;
  final VoidCallback onDailyPlay;
  final VoidCallback onDailyTap;

  @override
  Widget build(BuildContext context) {
    return _FeatureCard(
      title: '猜你喜欢',
      subtitle: daily.songs.isEmpty
          ? '献给此刻迈步的你'
          : daily.songs.first.title,
      imageUrl: daily.songs.isEmpty
          ? daily.coverUrl
          : daily.songs.first.coverUrl,
      gradient: const [Color(0xFFFFD88E), Color(0xFFFF8DA2)],
      onTap: onDailyTap,
      onPlay: onDailyPlay,
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
    required this.onPlay,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final List<Color> gradient;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final isCarMode = isLandscape && ThemeController.instance.carModeEnabled;

    final imageSize = isCarMode ? 82.0 : 64.0;
    final playSize = isCarMode ? 46.0 : 36.0;
    final playIconSize = isCarMode ? 26.0 : 20.0;
    final gap = isCarMode ? 14.0 : 10.0;
    final titleGap = isCarMode ? 7.0 : 6.0;
    final hintGap = isCarMode ? 4.0 : 3.0;
    final tagHPadding = isCarMode ? 9.0 : 7.0;
    final tagVPadding = isCarMode ? 4.5 : 3.0;
    final tagFontSize = isCarMode ? 13.5 : 11.0;
    final titleFontSize = isCarMode ? 17.5 : 13.0;
    final hintFontSize = isCarMode ? 13.0 : 11.0;
    final cardPadding = isCarMode ? const EdgeInsets.all(13) : const EdgeInsets.all(10);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: .06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: .10)
              : Colors.white.withValues(alpha: .92),
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
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: cardPadding,
            child: Row(
              children: [
                Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl == null
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: gradient),
                            ),
                            child: Icon(
                              Icons.album_rounded,
                              color: Colors.white,
                              size: isCarMode ? 36 : 28,
                            ),
                          )
                        : RetryableNetworkImage(
                            url: imageUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: 300,
                            cacheHeight: 300,
                            errorBuilder: (_, _, _) => DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: gradient),
                              ),
                              child: Icon(
                                Icons.music_note_rounded,
                                color: Colors.white,
                                size: isCarMode ? 32 : 26,
                              ),
                            ),
                          ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: tagHPadding,
                          vertical: tagVPadding,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(
                            alpha: isDark ? .18 : .10,
                          ),
                          borderRadius: BorderRadius.circular(isCarMode ? 8 : 7),
                        ),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: tagFontSize,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      SizedBox(height: titleGap),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: titleFontSize,
                              height: 1.2,
                            ),
                      ),
                      SizedBox(height: hintGap),
                      Text(
                        isCarMode ? '点击查看歌单 · 右侧播放' : '点击查看歌单',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: .70),
                          fontWeight: FontWeight.w600,
                          fontSize: hintFontSize,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: gap),
                _CirclePlayButton(size: playSize, iconSize: playIconSize, onTap: onPlay),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SongSection extends StatefulWidget {
  const _SongSection({
    super.key,
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
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: widget.auth,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            children: [
              _SectionHeader(
                title: widget.title,
                action: _CirclePlayButton(
                  tooltip: '播放',
                  size: 38,
                  iconSize: 22,
                  onTap: () =>
                      widget.onPlay(widget.songs.first, widget.songs),
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  // 桌面端（PC 软件逻辑）：纵向多列一次看全，外层页面纵滚，
                  // 不做左右翻页、不显示分页圆点。
                  if (isDesktopFormFactor) {
                    final int crossAxisCount;
                    if (maxWidth >= 1050) {
                      crossAxisCount = 3;
                    } else if (maxWidth >= 650) {
                      crossAxisCount = 2;
                    } else {
                      crossAxisCount = 1;
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int col = 0; col < crossAxisCount; col++) ...[
                          if (col > 0) const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                for (
                                  int i = col;
                                  i < widget.songs.length;
                                  i += crossAxisCount
                                )
                                  HomeSongRow(
                                    song: widget.songs[i],
                                    queue: widget.songs,
                                    onPlay: widget.onPlay,
                                    isLiked: widget.isLiked(widget.songs[i]),
                                    onLikeTap: () =>
                                        widget.onLikeTap(widget.songs[i]),
                                    auth: widget.auth,
                                    player: widget.player,
                                    onViewArtist: () =>
                                        widget.onViewArtist(widget.songs[i]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  }
                  final int crossAxisCount;
                  final int itemsPerPage;
                  if (maxWidth >= 1050) {
                    crossAxisCount = 3;
                    itemsPerPage = 9;
                  } else if (maxWidth >= 650) {
                    crossAxisCount = 2;
                    itemsPerPage = 6;
                  } else {
                    crossAxisCount = 1;
                    itemsPerPage = 3;
                  }

                  final rowCount = (itemsPerPage / crossAxisCount).ceil();
                  final pageCount = (widget.songs.length / itemsPerPage).ceil();

                  // 刷新后歌曲变少（或换页容量变化）时当前页可能越界：
                  // 圆点先按钳制后的页码显示，布局完成后把 PageView 跳回最后一页。
                  final effectivePage = _page.clamp(0, pageCount - 1);
                  if (_pageController.hasClients &&
                      _pageController.position.haveDimensions &&
                      (_pageController.page ?? 0) > pageCount - 1) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_pageController.hasClients) return;
                      _pageController.jumpToPage(pageCount - 1);
                    });
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: rowCount * 60.0,
                        child: HorizontalWheelPageScroll(
                          controller: _pageController,
                          child: PageView.builder(
                            controller: _pageController,
                            padEnds: false,
                            itemCount: pageCount,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (context, pageIndex) {
                              final start = pageIndex * itemsPerPage;
                              final end = (start + itemsPerPage).clamp(
                                0,
                                widget.songs.length,
                              );
                              final pageSongs = widget.songs.sublist(start, end);

                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      int col = 0;
                                      col < crossAxisCount;
                                      col++
                                    ) ...[
                                      if (col > 0) const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            for (
                                              int i = col;
                                              i < pageSongs.length;
                                              i += crossAxisCount
                                            )
                                              HomeSongRow(
                                                song: pageSongs[i],
                                                queue: widget.songs,
                                                onPlay: widget.onPlay,
                                                isLiked: widget.isLiked(
                                                  pageSongs[i],
                                                ),
                                                onLikeTap: () =>
                                                    widget.onLikeTap(pageSongs[i]),
                                                auth: widget.auth,
                                                player: widget.player,
                                                onViewArtist: () => widget
                                                    .onViewArtist(pageSongs[i]),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (pageCount > 1) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(pageCount, (i) {
                            final active = i == effectivePage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: active ? 16 : 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline
                                          .withValues(alpha: .3),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            );
                          }),
                        ),
                      ],
                    ],
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

/// 新歌速递横向区块。
class _TopSongRail extends StatelessWidget {
  const _TopSongRail({
    super.key,
    required this.songs,
    required this.onPlay,
    this.onTapTitle,
  });

  final List<Song> songs;
  final ValueChanged<Song> onPlay;
  final VoidCallback? onTapTitle;

  @override
  Widget build(BuildContext context) {
    // 车机首页只是二级页面的入口，只预览一行（6 首），与推荐歌单保持一致。
    final size = MediaQuery.sizeOf(context);
    final isCarMode =
        size.width > size.height && ThemeController.instance.carModeEnabled;
    if (isCarMode) {
      final preview = songs.length > 6 ? songs.sublist(0, 6) : songs;
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _SectionHeader(
                title: '新歌速递',
                action: const SizedBox.shrink(),
                onTap: onTapTitle,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: preview.length,
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                // 正方形封面 + 两行文字 ≈ 宽:高 = 0.72。
                childAspectRatio: 0.72,
              ),
              itemBuilder: (context, index) => _TopSongCard(
                song: preview[index],
                onTap: () => onPlay(preview[index]),
              ),
            ),
          ],
        ),
      );
    }
    // 桌面宽窗：转网格并让封面撑满格宽（此前复用横轨的固定 110 封面，
    // 格子比图大一圈，hover 时大片空白，见新歌速递截图箭头处）。
    return LayoutBuilder(
      builder: (context, constraints) {
        if (AdaptiveLayout.isDesktopGridWidth(constraints.maxWidth)) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _SectionHeader(
                    title: '新歌速递',
                    action: const SizedBox.shrink(),
                    onTap: onTapTitle,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: songs.length,
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 14,
                    // 正方形封面 + 两行文字 ≈ 宽:高 = 0.72。
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, index) => MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: _TopSongCard(
                      song: songs[index],
                      onTap: () => onPlay(songs[index]),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return AppHorizontalRail<Song>(
          title: '新歌速递',
          items: songs,
          height: 162,
          itemWidth: 110,
          topPadding: 20,
          onTapTitle: onTapTitle,
          itemBuilder: (context, song) =>
              _TopSongCard(song: song, onTap: () => onPlay(song)),
        );
      },
    );
  }
}

class _TopSongCard extends StatelessWidget {
  const _TopSongCard({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = isDesktopFormFactor;
    final cardRadius = isDesktop ? 8.0 : 14.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(cardRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 横轨下外层定宽 110；桌面网格下撑满格宽做正方形封面。
          final coverWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 110.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 桌面端：hover 封面浮现播放蒙层，点击 = 直接播放（与单击同义）；
              // 移动端 / 车机端 enabled=false，结构与接入前一致。
              CoverPlayOverlay(
                enabled: isDesktop,
                onPlay: onTap,
                borderRadius: cardRadius,
                buttonSize: 32,
                iconSize: 22,
                buttonColor: Colors.black54,
                iconColor: Colors.white,
                cover: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(cardRadius),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: .08)
                          : Colors.black.withValues(alpha: isDesktop ? .06 : .08),
                      width: 1,
                    ),
                    boxShadow: isDesktop
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? .14 : .06,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(cardRadius),
                    child: Artwork(url: song.coverUrl, size: coverWidth),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
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
          );
        },
      ),
    );
  }
}

class _PlaylistRail extends StatelessWidget {
  const _PlaylistRail({
    super.key,
    required this.playlists,
    required this.onTap,
    this.onPlay,
    this.onTapTitle,
  });

  final List<PlaylistSummary> playlists;
  final ValueChanged<PlaylistSummary> onTap;
  final ValueChanged<PlaylistSummary>? onPlay;
  final VoidCallback? onTapTitle;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    // 推荐歌单网格布局是车机专属，普通横屏用横向列表。
    final isCarMode = isLandscape && ThemeController.instance.carModeEnabled;

    if (isCarMode) {
      // 车机首页只是二级页面的入口，只预览一行（6 张），避免一次铺满全量。
      final preview = playlists.length > 6 ? playlists.sublist(0, 6) : playlists;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _SectionHeader(
                title: '推荐歌单',
                action: const SizedBox.shrink(),
                onTap: onTapTitle,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: preview.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 0.60,
              ),
              itemBuilder: (context, index) {
                final playlist = preview[index];
                return _PlaylistCard(
                  playlist: playlist,
                  onTap: () => onTap(playlist),
                  onPlay: onPlay == null ? null : () => onPlay!(playlist),
                );
              },
            ),
          ],
        ),
      );
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
              onTap: onTapTitle,
            ),
          ),
          const SizedBox(height: 12),
          // 门控统一读内容宽度（constraints.maxWidth），与其他分区一致；
          // 非桌面恒为 false，保持横轨（语义不变）。
          LayoutBuilder(
            builder: (context, constraints) {
              if (AdaptiveLayout.isDesktopGridWidth(constraints.maxWidth)) {
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: playlists.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.60,
                  ),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return _PlaylistCard(
                      playlist: playlist,
                      onTap: () => onTap(playlist),
                      onPlay: onPlay == null ? null : () => onPlay!(playlist),
                    );
                  },
                );
              }
              return SizedBox(
                height: 204,
                child: HorizontalWheelScroll(
                  builder: (context, controller) => ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    scrollDirection: Axis.horizontal,
                    itemCount: playlists.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return _PlaylistCard(
                        playlist: playlist,
                        onTap: () => onTap(playlist),
                        onPlay: onPlay == null ? null : () => onPlay!(playlist),
                        width: 128,
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
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.action = const SizedBox.shrink(),
    this.onTap,
  });

  final String title;
  final Widget action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget titleWidget = Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );

    Widget effectiveAction = action;
    if (onTap != null &&
        (action is SizedBox &&
            ((action as SizedBox).width == null ||
                (action as SizedBox).width == 0))) {
      effectiveAction = Icon(
        Icons.chevron_right_rounded,
        size: 22,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
      );
    }

    final content = Row(
      children: [
        Expanded(child: titleWidget),
        effectiveAction,
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }
    return content;
  }
}

/// 全局统一的淡雅圆形播放按钮：primary@.12 圆底 + primary 图标。
/// 用于推荐区头、猜你喜欢/新碟、自建歌单等所有列表播放入口。
class _CirclePlayButton extends StatelessWidget {
  const _CirclePlayButton({
    required this.onTap,
    this.size = 36,
    this.iconSize = 20,
    this.tooltip,
  });

  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: isDark ? .18 : .12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: colorScheme.primary,
        size: iconSize,
      ),
    );
    final ink = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: button,
      ),
    );
    if (tooltip == null) return ink;
    return Tooltip(message: tooltip!, child: ink);
  }
}

class _PlaylistCard extends StatefulWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    this.onPlay,
    this.width,
  });

  final PlaylistSummary playlist;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final double? width;

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = isDesktopFormFactor;
    final cardRadius = isDesktop ? 8.0 : 14.0;
    final hoverRadius = isDesktop ? 10.0 : cardRadius;
    const desktopInset = 6.0;

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final rawWidth = widget.width ?? constraints.maxWidth;
        final baseWidth = rawWidth.isInfinite ? 128.0 : rawWidth;
        final cardWidth = isDesktop
            ? (baseWidth - desktopInset * 2).clamp(0.0, double.infinity)
            : baseWidth;
        final size = cardWidth;

        final coverImage = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: .08)
                  : Colors.black.withValues(alpha: isDesktop ? .06 : .08),
              width: 1,
            ),
            boxShadow: isDesktop
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? .14 : .06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(cardRadius),
            child: Artwork(
              url: widget.playlist.coverUrl,
              size: size,
              borderRadius: cardRadius,
            ),
          ),
        );

        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CoverPlayOverlay(
              enabled: isDesktop && widget.onPlay != null,
              alignment: Alignment.bottomRight,
              borderRadius: cardRadius,
              buttonSize: 36,
              iconSize: 22,
              margin: const EdgeInsets.all(8),
              buttonColor: Theme.of(context).colorScheme.primary,
              iconColor: Theme.of(context).colorScheme.onPrimary,
              onPlay: () => widget.onPlay?.call(),
              tooltip: '播放歌单',
              isHovered: _hovered,
              darkenOnHover: false,
              cover: coverImage,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Text(
                widget.playlist.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: isDesktop ? 13.5 : 14,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.playlist.subtitle ?? _playCount(widget.playlist.playCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: isDesktop ? 12 : 12.5,
              ),
            ),
          ],
        );

        if (isDesktop) {
          return Padding(
            padding: const EdgeInsets.all(desktopInset),
            child: column,
          );
        }
        return column;
      },
    );

    final inkCard = InkWell(
      borderRadius: BorderRadius.circular(hoverRadius),
      onTap: widget.onTap,
      child: content,
    );

    final mouseCard = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: inkCard,
    );

    if (widget.width != null) {
      return SizedBox(
        width: widget.width,
        child: mouseCard,
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: mouseCard,
    );
  }
}

class _RadioSection extends StatefulWidget {
  const _RadioSection({
    super.key,
    required this.api,
    required this.player,
    required this.cache,
  });

  final MusicApi api;
  final PlayerController player;
  final CacheService cache;

  @override
  State<_RadioSection> createState() => _RadioSectionState();
}

class _RadioSectionState extends SwrSectionState<_RadioSection, _RadioData> {
  static _RadioData? _cachedData;

  String? _loadingStationId;

  @override
  CacheService get cache => widget.cache;

  @override
  _RadioData? get cachedData => _cachedData;

  @override
  set cachedData(_RadioData? value) => _cachedData = value;

  @override
  String get cacheKey => 'cache_radio';

  @override
  Duration get cacheTtl => AppConfig.radioCacheTtl;

  @override
  _RadioData decodeCache(Map<String, dynamic> json) => _RadioData.fromCache(json);

  @override
  Map<String, dynamic> encodeCache(_RadioData data) => data.toCache();

  @override
  bool hasContent(_RadioData data) =>
      data.recommended.isNotEmpty || data.groups.isNotEmpty;

  @override
  Future<_RadioData> fetchData() async {
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
      Toast.error('电台加载失败：${friendlyServiceErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _loadingStationId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isLandscape = screenSize.width > screenSize.height;
    // 电台双卡+网格布局是车机专属，普通横屏用原布局。
    final isCarMode = isLandscape && ThemeController.instance.carModeEnabled;

    // 磁盘恢复中（主数据 Future 尚未确定）：显示骨架，避免闪现空态。
    final future = sectionFuture;
    if (future == null) {
      return const _RadioSkeleton();
    }
    return FutureBuilder<_RadioData>(
      future: future,
      builder: (context, snapshot) {
        // 与推荐页/排行榜一致：优先显示内存/磁盘缓存，无缓存才走骨架/错误态。
        final data = snapshot.data ?? _cachedData;
        if (snapshot.connectionState == ConnectionState.waiting &&
            data == null) {
          return const _RadioSkeleton();
        }
        if (data == null && snapshot.hasError) {
          return _ErrorView(
            message: snapshot.error.toString(),
            onRetry: refresh,
          );
        }
        final radio = data ?? _RadioData.empty;

        if (isCarMode) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部均衡器刷新动画：刷新在途时出现，平时收起不占位。
                RefreshEqualizer(visible: showRefreshEqualizer),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: _RadioSectionTitle(
                    title: '推荐电台',
                    icon: Icons.radio_rounded,
                  ),
                ),
                if (radio.recommended.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: radio.recommended.length >= 2
                        // 有两个及以上推荐时，并排展示两张横卡
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _RadioHeroCard(
                                  station: radio.recommended[0],
                                  loading:
                                      _loadingStationId ==
                                      radio.recommended[0].id,
                                  onTap: () =>
                                      _playStation(radio.recommended[0]),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _RadioHeroCard(
                                  station: radio.recommended[1],
                                  loading:
                                      _loadingStationId ==
                                      radio.recommended[1].id,
                                  onTap: () =>
                                      _playStation(radio.recommended[1]),
                                ),
                              ),
                            ],
                          )
                        : _RadioHeroCard(
                            station: radio.recommended.first,
                            loading:
                                _loadingStationId ==
                                radio.recommended.first.id,
                            onTap: () =>
                                _playStation(radio.recommended.first),
                          ),
                  ),
                if (radio.recommended.length > 2) ...[
                  const SizedBox(height: 14),
                  _RadioStationGrid(
                    stations: radio.recommended.skip(2).toList(),
                    loadingStationId: _loadingStationId,
                    onTap: _playStation,
                  ),
                ],
                for (final group in radio.groups) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _RadioSectionTitle(
                      title: group.name,
                      icon: Icons.radio_rounded,
                      trailingText: '${group.stations.length} 个电台',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RadioStationGrid(
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
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部均衡器刷新动画：刷新在途时出现，平时收起不占位。
              RefreshEqualizer(visible: showRefreshEqualizer),
              _RadioSectionTitle(
                title: '推荐电台',
                icon: Icons.radio_rounded,
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
                  key: ValueKey('radio_rec_rail_$railResetEpoch'),
                  stations: radio.recommended.skip(1).toList(),
                  loadingStationId: _loadingStationId,
                  onTap: _playStation,
                ),
              ],
              for (final group in radio.groups) ...[
                const SizedBox(height: 24),
                _RadioSectionTitle(
                  title: group.name,
                  icon: Icons.radio_rounded,
                  trailingText: '${group.stations.length} 个电台',
                ),
                const SizedBox(height: 12),
                _RadioStationRail(
                  key: ValueKey('radio_group_${group.id}_$railResetEpoch'),
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

/// 电台统一小节标题：32 主色图标底 + 17 粗标题，与排行榜/首页白卡语言一致。
class _RadioSectionTitle extends StatelessWidget {
  const _RadioSectionTitle({
    required this.title,
    required this.icon,
    this.trailingText,
  });

  final String title;
  final IconData icon;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: isDark ? .18 : .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
          ),
        ),
        if (trailingText != null)
          Text(
            trailingText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
          ),
      ],
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final isCarMode = isLandscape && ThemeController.instance.carModeEnabled;

    final artworkSize = isCarMode ? 84.0 : 72.0;
    final cardPadding = isCarMode ? const EdgeInsets.all(14) : const EdgeInsets.all(12);
    final gap = isCarMode ? 14.0 : 12.0;
    final titleGap = isCarMode ? 7.0 : 6.0;
    final subtitleGap = isCarMode ? 4.0 : 3.0;
    final tagHPadding = isCarMode ? 9.0 : 7.0;
    final tagVPadding = isCarMode ? 4.5 : 3.0;
    final tagFontSize = isCarMode ? 13.5 : 11.0;
    final titleFontSize = isCarMode ? 18.0 : 15.0;
    final subtitleFontSize = isCarMode ? 14.0 : 12.0;

    // 与首页白卡统一：白底 16 圆角 + 描边 + 轻阴影，左侧封面 + 右侧信息 + 主色圆播钮。
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
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: cardPadding,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Artwork(
                      url: station.artworkUrl ?? station.bannerUrl,
                      size: artworkSize,
                      borderRadius: 12,
                      icon: Icons.radio_rounded,
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: tagHPadding,
                          vertical: tagVPadding,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: isDark ? .18 : .10),
                          borderRadius: BorderRadius.circular(isCarMode ? 8 : 7),
                        ),
                        child: Text(
                          '推荐电台',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: tagFontSize,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      SizedBox(height: titleGap),
                      Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: titleFontSize,
                              height: 1.2,
                            ),
                      ),
                      SizedBox(height: subtitleGap),
                      Text(
                        station.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              fontSize: subtitleFontSize,
                            ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: gap),
                _RadioPlayBadge(loading: loading),
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
    super.key,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // 桌面宽窗直接复用车机网格组件（同参数、同卡片），保持视觉一致。
        if (AdaptiveLayout.isDesktopGridWidth(constraints.maxWidth)) {
          return _RadioStationGrid(
            stations: stations,
            loadingStationId: loadingStationId,
            onTap: onTap,
          );
        }
        // 卡片内容高度充足（封面116 + 标题 + 副标题），轨道188彻底杜绝底部溢出且呼吸感匀称。
        return SizedBox(
          height: 188,
          child: HorizontalWheelScroll(
            builder: (context, controller) => ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: stations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final station = stations[index];
                return _RadioStationCard(
                  station: station,
                  loading: loadingStationId == station.id,
                  onTap: () => onTap(station),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _RadioStationGrid extends StatelessWidget {
  const _RadioStationGrid({
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
    // 格子纵横比给足文字与留白空间，避免在大屏网格下溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final count = (maxWidth / 170).floor().clamp(2, 7);
        const spacing = 12.0;
        final cellWidth = (maxWidth - spacing * (count - 1)) / count;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: stations.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: cellWidth / (cellWidth + 56),
          ),
          itemBuilder: (context, index) {
            final station = stations[index];
            return _RadioStationCard(
              station: station,
              loading: loadingStationId == station.id,
              onTap: () => onTap(station),
              width: null,
            );
          },
        );
      },
    );
  }
}

class _RadioStationCard extends StatelessWidget {
  const _RadioStationCard({
    required this.station,
    required this.loading,
    required this.onTap,
    this.width = 132,
  });

  final FmStation station;
  final bool loading;
  final VoidCallback onTap;
  /// 横滑轨道传固定宽；网格传 null 让卡片撑满格子，封面随格宽自适应。
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 与排行榜新歌卡统一的白卡：圆角 16 + 描边 + 轻阴影，封面圆角 + 右下淡蓝播钮。
    final card = Container(
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
            borderRadius: BorderRadius.circular(16),
            onTap: loading ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 116.0;
                      return Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox.square(
                                dimension: side,
                                child: Artwork(
                                  url: station.artworkUrl,
                                  size: side,
                                  borderRadius: 12,
                                  icon: Icons.radio_rounded,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: _RadioPlayBadge(loading: loading, compact: true),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            height: 1.2,
                          ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      station.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11.5,
                            height: 1.2,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    final width = this.width;
    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }
}

class _RadioPlayBadge extends StatelessWidget {
  const _RadioPlayBadge({required this.loading, this.compact = false});

  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.sizeOf(context);
    final isLandscape = screenSize.width > screenSize.height;
    final isCarMode = isLandscape && ThemeController.instance.carModeEnabled;

    // 与全局/推荐页圆形播钮统一：清爽淡蓝底 + 主色图标。大卡小卡统一实底淡蓝，杜绝泛灰。
    final size = compact ? 30.0 : (isCarMode ? 46.0 : 38.0);
    final iconSize = compact ? 18.0 : (isCarMode ? 26.0 : 22.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.primary.withValues(alpha: .28)
            : const Color(0xFFE8F2FF),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: isDark ? .20 : .12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: loading
            ? SizedBox.square(
                dimension: compact ? 14 : 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  color: colorScheme.primary,
                ),
              )
            : Icon(
                Icons.play_arrow_rounded,
                color: colorScheme.primary,
                size: iconSize,
              ),
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
          const _SkeletonBox(width: 140, height: 32, radius: 10),
          const SizedBox(height: 12),
          const _SkeletonBox(width: double.infinity, height: 100, radius: 16),
          const SizedBox(height: 22),
          const _SkeletonBox(width: 120, height: 32, radius: 10),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return _SkeletonBox(
                  width: 132,
                  height: 190,
                  radius: 16,
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
    // 绝不把 ApiException / URL 等原始异常透出到页面：统一转成可行动的友好文案。
    final friendly = friendlyServiceErrorMessage(message);
    final colorScheme = Theme.of(context).colorScheme;
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
    );
  }
}

/// 首页推荐 tab 的组合数据模型（每日推荐 + 推荐歌单 + 新歌速递）。
/// 公开可见是 [HomePageState] 作为 `SwrSectionState<HomePage, HomeData>`
/// 的泛型参数所需；仅在首页内部使用。
class HomeData {
  const HomeData({
    required this.daily,
    required this.playlists,
    this.topSongs = const [],
  });

  final DailyRecommend daily;
  final List<PlaylistSummary> playlists;
  final List<Song> topSongs;
}

class _RadioData {
  const _RadioData({required this.recommended, required this.groups});

  static const empty = _RadioData(recommended: [], groups: []);

  final List<FmStation> recommended;
  final List<FmClassGroup> groups;

  Map<String, dynamic> toCache() {
    return {
      'recommended': recommended.map((s) => s.toCache()).toList(),
      'groups': groups.map((g) => g.toCache()).toList(),
    };
  }

  factory _RadioData.fromCache(Map<String, dynamic> json) {
    return _RadioData(
      recommended: (json['recommended'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FmStation.fromCache)
          .where((s) => s.id.isNotEmpty)
          .toList(),
      groups: (json['groups'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FmClassGroup.fromCache)
          .toList(),
    );
  }
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

class _CarQuickStatsPills extends StatefulWidget {
  const _CarQuickStatsPills({
    required this.auth,
    required this.player,
    required this.onSwitchToMyTab,
    required this.api,
    this.isSideBySide = false,
  });

  final AuthController auth;
  final PlayerController player;
  final VoidCallback onSwitchToMyTab;
  final MusicApi api;
  final bool isSideBySide;

  @override
  State<_CarQuickStatsPills> createState() => _CarQuickStatsPillsState();
}

class _CarQuickStatsPillsState extends State<_CarQuickStatsPills> {
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    _loadHistoryCount();
  }

  Future<void> _loadHistoryCount() async {
    try {
      final count = await widget.player.getPlaybackHistoryCount();
      if (mounted) {
        setState(() {
          _historyCount = count;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 外层已有左右 18 留白，这里只留顶部间距，保证与上方特征卡左右对齐。
    const padding = EdgeInsets.only(top: 20);
    return Padding(
      padding: widget.isSideBySide ? EdgeInsets.zero : padding,
      child: Row(
        children: [
          Expanded(
            child: _PillCard(
              title: '已播歌曲',
              value: '$_historyCount',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlaybackHistoryPage(
                    api: widget.api,
                    auth: widget.auth,
                    player: widget.player,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PillCard(
              title: '收藏歌曲',
              value: '${widget.auth.likedCount}',
              onTap: () {
                if (widget.auth.likedPlaylist != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailPage(
                        api: widget.api,
                        auth: widget.auth,
                        player: widget.player,
                        playlist: widget.auth.likedPlaylist!,
                      ),
                    ),
                  );
                } else {
                  Toast.info('暂无收藏歌单');
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PillCard(
              title: '自建歌单',
              value: '${widget.auth.createdPlaylists.length}',
              onTap: widget.onSwitchToMyTab,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillCard extends StatelessWidget {
  const _PillCard({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: .06) : Colors.white,
        borderRadius: BorderRadius.circular(28),
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
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _CirclePlayButton(size: 36, iconSize: 20, onTap: onTap),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
