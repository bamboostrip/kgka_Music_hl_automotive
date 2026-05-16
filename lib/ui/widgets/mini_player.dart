import 'dart:ui';

import 'package:flutter/material.dart';

import '../../controllers/player_controller.dart';
import '../pages/player_page.dart';
import 'artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final song = player.currentSong;
        if (song == null) {
          return const SizedBox.shrink();
        }

        final progress = player.duration.inMilliseconds == 0
            ? 0.0
            : (player.position.inMilliseconds / player.duration.inMilliseconds)
                  .clamp(0.0, 1.0);
        final colorScheme = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHighest.withValues(alpha: .72)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: .64),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: .38),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerPage(player: player),
                    ),
                  ),
                  child: SizedBox(
                    height: 64,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    7,
                                    8,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Artwork(
                                        url: song.coverUrl,
                                        size: 48,
                                        borderRadius: 6,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 15,
                                                  ),
                                            ),
                                            Text(
                                              song.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: player.isPlaying ? '暂停' : '播放',
                                        onPressed: player.isPreparing
                                            ? null
                                            : player.togglePlay,
                                        icon: Icon(
                                          player.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: colorScheme.onSurface,
                                          size: 30,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '播放页',
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PlayerPage(player: player),
                                              ),
                                            ),
                                        icon: Icon(
                                          Icons.queue_music_rounded,
                                          color: colorScheme.onSurface,
                                          size: 29,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              LinearProgressIndicator(
                                value: progress,
                                minHeight: 2,
                                color: colorScheme.primary,
                                backgroundColor: colorScheme.primary.withValues(
                                  alpha: .12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (player.errorMessage case final message?)
                          Positioned(
                            left: 74,
                            right: 88,
                            bottom: 4,
                            child: Text(
                              message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.error,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
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
