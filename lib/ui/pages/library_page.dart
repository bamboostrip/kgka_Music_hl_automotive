import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';
import 'playlist_detail_page.dart';

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
          builder: (_) =>
              PlaylistDetailPage(api: api, player: player, playlist: playlist),
        ),
      );
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
              const SliverToBoxAdapter(child: _MyHeader()),
              if (!auth.isLoggedIn)
                SliverToBoxAdapter(child: _LoginPanel(auth: auth))
              else ...[
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
            ],
          );
        },
      ),
    );
  }
}

class _MyHeader extends StatelessWidget {
  const _MyHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Text(
        '我的',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 26,
        ),
      ),
    );
  }
}

class _LoginPanel extends StatefulWidget {
  const _LoginPanel({required this.auth});

  final AuthController auth;

  @override
  State<_LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<_LoginPanel> {
  final _mobileController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _mobileController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 160),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '登录 KA Music',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '同步你的歌单和账号信息。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                  labelText: '手机号',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.password_rounded),
                        labelText: '验证码',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: widget.auth.isLoading
                        ? null
                        : () => widget.auth.sendCode(
                            _mobileController.text.trim(),
                          ),
                    child: const Text('获取'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: widget.auth.isLoading
                    ? null
                    : () => widget.auth.login(
                        _mobileController.text.trim(),
                        _codeController.text.trim(),
                      ),
                child: widget.auth.isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
              if (widget.auth.errorMessage case final message?) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
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
          IconButton(
            tooltip: '刷新',
            onPressed: auth.isLoading ? null : auth.refreshProfile,
            icon: const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: '退出登录',
            onPressed: auth.logout,
            icon: const Icon(Icons.logout_rounded),
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
              value: '${auth.likedPlaylist?.songCount ?? 0}',
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
