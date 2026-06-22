import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/download_controller.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import 'cloud_drive_page.dart';
import 'downloaded_songs_page.dart';
import 'playlist_detail_page.dart';
import 'settings_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.downloads,
    required this.theme,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final DownloadController downloads;
  final ThemeController theme;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          api: widget.api,
          auth: widget.auth,
          player: widget.player,
          theme: widget.theme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        // 顶部渐变背景（仅顶部区域，淡淡过渡到透明）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [
                        Color(0xFF10233A),
                        Color(0xFF0B1828),
                        Color(0x0006070A),
                      ]
                    : const [
                        Color(0xFFEAF3FF),
                        Color(0xFFF2F7FD),
                        Color(0x00FFFFFF),
                      ],
                stops: const [0, .6, 1],
              ),
            ),
          ),
        ),
        // 内容层
        SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: widget.auth,
            builder: (context, _) {
              final created = widget.auth.createdPlaylists;
              final collected = widget.auth.collectedPlaylists;
              final albums = widget.auth.collectedAlbums;

              return CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '我的',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                  ),
                            ),
                          ),
                          IconButton(
                            tooltip: '设置',
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Account info
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                      child: _AccountRow(auth: widget.auth),
                    ),
                  ),
                  // Quick action cards (horizontal scrollable)
                  SliverToBoxAdapter(
                    child: _QuickActionRow(
                      auth: widget.auth,
                      downloads: widget.downloads,
                      player: widget.player,
                      api: widget.api,
                      onOpenLiked: widget.auth.likedPlaylist == null
                          ? null
                          : () => _openPlaylist(widget.auth.likedPlaylist!),
                      onOpenDownloads: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DownloadedSongsPage(
                            api: widget.api,
                            auth: widget.auth,
                            player: widget.player,
                            downloads: widget.downloads,
                          ),
                        ),
                      ),
                      onOpenCloudDrive: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CloudDrivePage(
                            api: widget.api,
                            auth: widget.auth,
                            player: widget.player,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Tab 标签栏：创建 / 收藏 / 专辑
                  SliverToBoxAdapter(
                    child: _PlaylistTabBar(
                      controller: _tabController,
                      createdCount: created.length,
                      collectedCount: collected.length,
                      albumCount: albums.length,
                    ),
                  ),
                  // 当前 Tab 对应的歌单列表
                  SliverToBoxAdapter(
                    child: _PlaylistTabView(
                      controller: _tabController,
                      created: created,
                      collected: collected,
                      albums: albums,
                      onOpen: _openPlaylist,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- Account row (no card background) ---

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profile = auth.profile;

    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: profile?.avatarUrl == null
              ? Icon(Icons.person_rounded, color: colorScheme.primary)
              : Image.network(profile!.avatarUrl!, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile?.nickname ?? 'KA Music 用户',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                '已登录',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Quick action row (horizontal scrollable cards) ---

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.auth,
    required this.downloads,
    required this.player,
    required this.api,
    required this.onOpenLiked,
    required this.onOpenDownloads,
    required this.onOpenCloudDrive,
  });

  final AuthController auth;
  final DownloadController downloads;
  final PlayerController player;
  final MusicApi api;
  final VoidCallback? onOpenLiked;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenCloudDrive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 0, 0),
      child: SizedBox(
        height: 120,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 18),
          children: [
            _QuickActionCard(
              icon: Icons.favorite_rounded,
              iconColor: const Color.fromARGB(176, 255, 99, 151),
              subtitle: '${auth.likedCount} 首歌曲',
              title: '我喜欢',
              onTap: onOpenLiked,
            ),
            const SizedBox(width: 10),
            _QuickActionCard(
              icon: Icons.cloud_rounded,
              iconColor: const Color.fromARGB(200, 88, 156, 245),
              subtitle: '云盘音乐',
              title: '云盘',
              onTap: onOpenCloudDrive,
            ),
            const SizedBox(width: 10),
            AnimatedBuilder(
              animation: downloads,
              builder: (context, _) {
                return _QuickActionCard(
                  icon: Icons.download_rounded,
                  iconColor: Theme.of(context).colorScheme.primary,
                  subtitle: '${downloads.downloadedSongs.length} 首歌曲',
                  title: '已下载',
                  onTap: onOpenDownloads,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.subtitle,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String subtitle;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 93,
      margin: const EdgeInsets.only(right: 0),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Tab 标签栏 ---

class _PlaylistTabBar extends StatelessWidget {
  const _PlaylistTabBar({
    required this.controller,
    required this.createdCount,
    required this.collectedCount,
    required this.albumCount,
  });

  final TabController controller;
  final int createdCount;
  final int collectedCount;
  final int albumCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Row(
              children: [
                Expanded(
                  child: _TabItem(
                    label: '创建',
                    count: createdCount,
                    selected: controller.index == 0,
                    onTap: () => controller.animateTo(0),
                  ),
                ),
                Expanded(
                  child: _TabItem(
                    label: '收藏',
                    count: collectedCount,
                    selected: controller.index == 1,
                    onTap: () => controller.animateTo(1),
                  ),
                ),
                Expanded(
                  child: _TabItem(
                    label: '专辑',
                    count: albumCount,
                    selected: controller.index == 2,
                    onTap: () => controller.animateTo(2),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label),
              if (count > 0) ...[
                const TextSpan(text: ' '),
                TextSpan(
                  text: '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colorScheme.onPrimary.withValues(alpha: .78)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// --- Tab 内容视图 ---

class _PlaylistTabView extends StatelessWidget {
  const _PlaylistTabView({
    required this.controller,
    required this.created,
    required this.collected,
    required this.albums,
    required this.onOpen,
  });

  final TabController controller;
  final List<PlaylistSummary> created;
  final List<PlaylistSummary> collected;
  final List<PlaylistSummary> albums;
  final void Function(PlaylistSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final lists = [created, collected, albums];
          final current = lists[controller.index.clamp(0, 2)];
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: current.isEmpty
                ? _EmptyGroup(key: ValueKey('empty_${controller.index}'))
                : _PlaylistGroup(
                    key: ValueKey('group_${controller.index}'),
                    playlists: current,
                    onOpen: onOpen,
                  ),
          );
        },
      ),
    );
  }
}

class _EmptyGroup extends StatelessWidget {
  const _EmptyGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '这里还没有内容',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Playlist group with dividers (no card background) ---

class _PlaylistGroup extends StatelessWidget {
  const _PlaylistGroup({
    super.key,
    required this.playlists,
    required this.onOpen,
  });

  final List<PlaylistSummary> playlists;
  final void Function(PlaylistSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            for (var i = 0; i < playlists.length; i++) ...[
              _PlaylistRow(
                playlist: playlists[i],
                onTap: () => onOpen(playlists[i]),
              ),
              if (i < playlists.length - 1)
                Divider(
                  height: 1,
                  indent: 62,
                  color: colorScheme.outlineVariant.withValues(alpha: .3),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Playlist row ---

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Artwork(url: playlist.coverUrl, size: 44, borderRadius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.songCount == null
                        ? (playlist.subtitle ?? '歌单')
                        : '${playlist.songCount} 首歌',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
