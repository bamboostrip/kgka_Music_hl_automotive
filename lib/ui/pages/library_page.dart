import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/download_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import 'downloaded_songs_page.dart';
import 'playlist_detail_page.dart';
import 'settings_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
    required this.downloads,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;
  final DownloadController downloads;

  @override
  Widget build(BuildContext context) {
    void openPlaylist(PlaylistSummary playlist) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailPage(
            api: api,
            auth: auth,
            player: player,
            playlist: playlist,
          ),
        ),
      );
    }

    void openSettings() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SettingsPage(api: api, auth: auth, player: player),
        ),
      );
    }

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
            animation: auth,
            builder: (context, _) {
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
                        onPressed: openSettings,
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
                  child: _AccountRow(auth: auth),
                ),
              ),
              // Quick action cards (horizontal scrollable)
              SliverToBoxAdapter(
                child: _QuickActionRow(
                  auth: auth,
                  downloads: downloads,
                  onOpenLiked: auth.likedPlaylist == null
                      ? null
                      : () => openPlaylist(auth.likedPlaylist!),
                  onOpenDownloads: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DownloadedSongsPage(
                        api: api,
                        auth: auth,
                        player: player,
                        downloads: downloads,
                      ),
                    ),
                  ),
                ),
              ),
              // Created playlists
              if (auth.createdPlaylists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _PlaylistSectionHeader(
                    title: '创建的歌单',
                    count: auth.createdPlaylists.length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PlaylistGroup(
                    playlists: auth.createdPlaylists,
                    onOpen: openPlaylist,
                  ),
                ),
              ],
              // Collected playlists
              if (auth.collectedPlaylists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _PlaylistSectionHeader(
                    title: '收藏的歌单',
                    count: auth.collectedPlaylists.length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PlaylistGroup(
                    playlists: auth.collectedPlaylists,
                    onOpen: openPlaylist,
                  ),
                ),
              ],
              // Collected albums
              if (auth.collectedAlbums.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _PlaylistSectionHeader(
                    title: '收藏的专辑',
                    count: auth.collectedAlbums.length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _PlaylistGroup(
                    playlists: auth.collectedAlbums,
                    onOpen: openPlaylist,
                  ),
                ),
              ],
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
    required this.onOpenLiked,
    required this.onOpenDownloads,
  });

  final AuthController auth;
  final DownloadController downloads;
  final VoidCallback? onOpenLiked;
  final VoidCallback onOpenDownloads;

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
            const SizedBox(width: 12),
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
      width: 104,
      margin: const EdgeInsets.only(right: 0),
      child: Material(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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

// --- Section header ---

class _PlaylistSectionHeader extends StatelessWidget {
  const _PlaylistSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Playlist group with dividers (no card background) ---

class _PlaylistGroup extends StatelessWidget {
  const _PlaylistGroup({required this.playlists, required this.onOpen});

  final List<PlaylistSummary> playlists;
  final void Function(PlaylistSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: DecoratedBox(
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
