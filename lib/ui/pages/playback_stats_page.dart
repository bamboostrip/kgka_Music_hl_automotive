import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../../services/playback_stats_service.dart';
import '../widgets/toast.dart';

/// 播放统计页面：展示累计播放次数、听歌时长、最常听歌手/歌曲 Top 10。
class PlaybackStatsPage extends StatefulWidget {
  const PlaybackStatsPage({super.key, required this.player});

  final PlayerController player;

  @override
  State<PlaybackStatsPage> createState() => _PlaybackStatsPageState();
}

class _PlaybackStatsPageState extends State<PlaybackStatsPage> {
  Future<PlaybackStats>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.player.getPlaybackStats();
    });
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('清空播放统计'),
          content: const Text('确定要清空全部播放统计吗？此操作不可恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await widget.player.clearPlaybackStats();
    Toast.success('已清空播放统计');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放统计'),
        actions: [
          FutureBuilder<PlaybackStats>(
            future: _future,
            builder: (context, snapshot) {
              final hasData = snapshot.hasData;
              final stats = snapshot.data;
              final hasStats = hasData && stats != null &&
                  (stats.totalPlays > 0 ||
                      stats.totalListenTime > Duration.zero);
              return IconButton(
                tooltip: '清空统计',
                onPressed: hasStats ? _confirmClear : null,
                icon: const Icon(Icons.delete_sweep_outlined),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<PlaybackStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(message: '${snapshot.error}');
          }
          final stats = snapshot.data ?? const PlaybackStats();
          if (stats.totalPlays == 0 &&
              stats.totalListenTime == Duration.zero) {
            return const _EmptyView();
          }
          return _StatsContent(stats: stats);
        },
      ),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.stats});

  final PlaybackStats stats;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _SectionHeader(title: '总览'),
        const SizedBox(height: 8),
        _StatsCard(
          children: [
            _StatRow(
              icon: Icons.play_circle_outline_rounded,
              iconColor: Theme.of(context).colorScheme.primary,
              title: '累计播放',
              value: '${stats.totalPlays} 次',
            ),
            const _StatsDivider(),
            _StatRow(
              icon: Icons.timer_outlined,
              iconColor: Theme.of(context).colorScheme.primary,
              title: '累计听歌时长',
              value: stats.formattedListenTime,
            ),
            const _StatsDivider(),
            _StatRow(
              icon: Icons.calendar_today_outlined,
              iconColor: Theme.of(context).colorScheme.primary,
              title: '首次播放',
              value: stats.firstPlayDate == null
                  ? '—'
                  : _formatDate(stats.firstPlayDate!),
            ),
          ],
        ),
        if (stats.topArtists.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: '最常听歌手 Top 10'),
          const SizedBox(height: 8),
          _StatsCard(
            children: [
              for (var i = 0; i < stats.topArtists.length; i++) ...[
                if (i > 0) const _StatsDivider(),
                _RankRow(
                  rank: i + 1,
                  title: stats.topArtists[i].key,
                  count: stats.topArtists[i].value,
                ),
              ],
            ],
          ),
        ],
        if (stats.topSongs.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: '最常听歌曲 Top 10'),
          const SizedBox(height: 8),
          _StatsCard(
            children: [
              for (var i = 0; i < stats.topSongs.length; i++) ...[
                if (i > 0) const _StatsDivider(),
                _RankRow(
                  rank: i + 1,
                  title: stats.topSongs[i].key,
                  count: stats.topSongs[i].value,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.children});

  final List<Widget> children;

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
        child: Column(children: children),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.title,
    required this.count,
  });

  final int rank;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTop3 = rank <= 3;
    final rankColor = isTop3 ? colorScheme.primary : colorScheme.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count 次',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsDivider extends StatelessWidget {
  const _StatsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 62,
      color: Theme.of(context)
          .colorScheme
          .outlineVariant
          .withValues(alpha: .4),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无播放统计',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '播放歌曲后会在这里看到统计数据',
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            const Text('加载失败', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
