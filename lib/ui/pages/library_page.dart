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
          builder: (_) => SettingsPage(auth: auth, player: player),
        ),
      );
    }

    Future<void> createPlaylist() async {
      final result = await showDialog<_CreatePlaylistResult>(
        context: context,
        builder: (context) => const _CreatePlaylistDialog(),
      );
      if (result == null || result.name.trim().isEmpty) return;
      try {
        await auth.createPlaylist(result.name, private: result.private);
        if (auth.errorMessage != null) {
          throw Exception(auth.errorMessage);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('歌单已创建')));
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('创建失败：$error')));
        }
      }
    }

    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: auth,
        builder: (context, _) {
          final createdPlaylists = auth.createdPlaylists;
          final collectedPlaylists = auth.collectedPlaylists;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _MyHeader(
                  onCreateTap: createPlaylist,
                  onSettingsTap: openSettings,
                ),
              ),
              SliverToBoxAdapter(child: _AccountCard(auth: auth)),
              SliverToBoxAdapter(
                child: _QuickStats(
                  auth: auth,
                  onLikedTap: auth.likedPlaylist == null
                      ? null
                      : () => openPlaylist(auth.likedPlaylist!),
                ),
              ),
              if (auth.playlists.isEmpty)
                const SliverToBoxAdapter(child: _EmptyPlaylists())
              else ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: '创建的歌单',
                    count: createdPlaylists.length,
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    collectedPlaylists.isEmpty ? 160 : 20,
                  ),
                  sliver: SliverList.separated(
                    itemCount: createdPlaylists.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final playlist = createdPlaylists[index];
                      return _PlaylistRow(
                        playlist: playlist,
                        onTap: () => openPlaylist(playlist),
                      );
                    },
                  ),
                ),
                if (collectedPlaylists.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: '收藏的歌单',
                      count: collectedPlaylists.length,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 160),
                    sliver: SliverList.separated(
                      itemCount: collectedPlaylists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final playlist = collectedPlaylists[index];
                        return _PlaylistRow(
                          playlist: playlist,
                          onTap: () => openPlaylist(playlist),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MyHeader extends StatelessWidget {
  const _MyHeader({required this.onCreateTap, required this.onSettingsTap});

  final VoidCallback onCreateTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '我的',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 26,
              ),
            ),
          ),
          IconButton(
            tooltip: '新建歌单',
            onPressed: onCreateTap,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: onSettingsTap,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }
}

class _CreatePlaylistResult {
  const _CreatePlaylistResult({required this.name, required this.private});

  final String name;
  final bool private;
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final _controller = TextEditingController();
  var _private = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建歌单'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '歌单名称'),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _private,
            onChanged: (value) => setState(() => _private = value),
            title: const Text('设为隐私'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _CreatePlaylistResult(
                name: _controller.text.trim(),
                private: _private,
              ),
            );
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final profile = auth.profile;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: profile?.avatarUrl == null
                ? Icon(Icons.person_rounded, color: colorScheme.primary)
                : Image.network(profile!.avatarUrl!, fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.nickname ?? 'KA Music 用户',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '已登录',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.auth, required this.onLikedTap});

  final AuthController auth;
  final VoidCallback? onLikedTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.queue_music_rounded,
              label: '歌单',
              value: '${auth.playlists.length}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.favorite_rounded,
              label: '我喜欢',
              value: '${auth.likedCount}',
              onTap: onLikedTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          Text(
            '$count 个',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 160),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            '这里会显示你收藏和创建的歌单。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});

  final PlaylistSummary playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
            Artwork(url: playlist.coverUrl, size: 58, borderRadius: 10),
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
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    playlist.songCount == null
                        ? (playlist.subtitle ?? '歌单')
                        : '${playlist.songCount} 首歌',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
