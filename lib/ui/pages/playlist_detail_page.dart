import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.api,
    required this.player,
    required this.playlist,
  });

  final MusicApi api;
  final PlayerController player;
  final PlaylistSummary playlist;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  late Future<PlaylistDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.playlistDetail(widget.playlist.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<PlaylistDetail>(
        future: _future,
        builder: (context, snapshot) {
          final detail = snapshot.data;
          final info = detail?.info ?? widget.playlist;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                stretch: true,
                expandedHeight: 198,
                surfaceTintColor: Colors.transparent,
                title: Text(
                  info.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: _HeroHeader(info: info),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _DetailError(
                    message: snapshot.error.toString(),
                    onRetry: () => setState(() {
                      _future = widget.api.playlistDetail(widget.playlist.id);
                    }),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _Actions(
                    count: detail!.songs.length,
                    onPlay: detail.songs.isEmpty
                        ? null
                        : () => widget.player.playSong(
                            detail.songs.first,
                            queue: detail.songs,
                          ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 34),
                  sliver: SliverList.separated(
                    itemCount: detail.songs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final song = detail.songs[index];
                      return _SongRow(
                        song: song,
                        index: index + 1,
                        onTap: () =>
                            widget.player.playSong(song, queue: detail.songs),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.info});

  final PlaylistSummary info;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: isDark ? .28 : .18),
            const Color(0xFFDCEEFF).withValues(alpha: isDark ? .08 : .92),
            Theme.of(context).scaffoldBackgroundColor,
          ],
          stops: const [0, .58, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              final artworkSize = compact ? 90.0 : 102.0;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Artwork(
                    url: info.coverUrl,
                    size: artworkSize,
                    borderRadius: 16,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '歌单',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          info.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          info.subtitle ?? _detailMeta(info),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _detailMeta(info),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.count, required this.onPlay});

  final int count;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count 首歌曲',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放全部'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.index,
    required this.onTap,
  });

  final Song song;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$index',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatDuration(song.duration),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 42),
          const SizedBox(height: 12),
          Text('歌单加载失败', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
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

String _detailMeta(PlaylistSummary info) {
  final parts = <String>[];
  if (info.songCount != null) {
    parts.add('${info.songCount} 首歌');
  }
  if (info.playCount != null) {
    parts.add(_playCount(info.playCount));
  }
  return parts.isEmpty ? '来自 KA Music' : parts.join(' · ');
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
