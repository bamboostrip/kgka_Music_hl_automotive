import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import 'playlist_detail_page.dart';
import 'settings_page.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

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

    return SafeArea(
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
                                fontSize: 24,
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
              // Liked songs card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                  child: _LikedCard(
                    auth: auth,
                    onTap: auth.likedPlaylist == null
                        ? null
                        : () => openPlaylist(auth.likedPlaylist!),
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

// --- Liked songs card (standalone) ---

class _LikedCard extends StatelessWidget {
  const _LikedCard({required this.auth, required this.onTap});

  final AuthController auth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(176, 255, 99, 151),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我喜欢',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${auth.likedCount} 首歌曲',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.outline,
              ),
            ],
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
