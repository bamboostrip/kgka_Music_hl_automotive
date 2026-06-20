import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import 'artwork.dart';

class SongSheetAction {
  const SongSheetAction({
    required this.icon,
    required this.title,
    this.subtitle,
    this.danger = false,
    this.isGrid = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final bool isGrid;
  final FutureOr<void> Function() onTap;
}

Future<void> showSongActionSheet({
  required BuildContext context,
  required Song song,
  required List<SongSheetAction> actions,
}) {
  final gridActions = actions.where((a) => a.isGrid).toList();
  final listActions = actions.where((a) => !a.isGrid).toList();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      final colorScheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Song info
                Row(
                children: [
                  Artwork(url: song.coverUrl, size: 52, borderRadius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Actions card (grid + list in one unified card)
              if (gridActions.isNotEmpty || listActions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Material(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Grid actions (icon + text, 3-column grid)
                      if (gridActions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var row = 0;
                                  row * 3 < gridActions.length;
                                  row++)
                                Row(
                                  children: [
                                    for (var col = 0; col < 3; col++)
                                      Expanded(
                                        child: row * 3 + col < gridActions.length
                                            ? _GridItem(
                                                action: gridActions[row * 3 + col],
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      // Divider between grid and list
                      if (gridActions.isNotEmpty && listActions.isNotEmpty)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      // List actions
                      for (var index = 0;
                          index < listActions.length;
                          index++) ...[
                        _SongActionTile(action: listActions[index]),
                        if (index != listActions.length - 1)
                          const Divider(height: 1, indent: 58),
                      ],
                    ],
                  ),
                ),
              ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _GridItem extends StatelessWidget {
  const _GridItem({required this.action});

  final SongSheetAction action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = action.danger ? colorScheme.error : colorScheme.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => action.onTap(),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(action.icon, color: color, size: 21),
          ),
          const SizedBox(height: 5),
          Text(
            action.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (action.subtitle != null)
              Text(
                action.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
          ],
        ),
    );
  }
}

Future<void> showAddToPlaylistSheet({
  required BuildContext context,
  required AuthController auth,
  required Song song,
}) async {
  final playlists = auth.createdPlaylists
      .where((playlist) => playlist.listId?.isNotEmpty == true)
      .toList();
  final picked = await showModalBottomSheet<PlaylistSummary>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      final colorScheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '添加到歌单',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '还没有可添加的歌单',
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                )
              else
                Flexible(
                  child: Material(
                    color: Colors.transparent,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Artwork(
                            url: playlist.coverUrl,
                            size: 46,
                            borderRadius: 9,
                          ),
                          title: Text(
                            playlist.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${playlist.songCount ?? 0} 首歌'),
                          onTap: () => Navigator.of(context).pop(playlist),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  if (picked == null || !context.mounted) return;

  try {
    await auth.addSongToPlaylist(picked, song);
    if (auth.errorMessage != null) {
      throw Exception(auth.errorMessage);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加到 ${picked.title}')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加失败：$error')));
    }
  }
}

Future<void> addSongToQueueWithFeedback({
  required BuildContext context,
  required PlayerController player,
  required Song song,
}) async {
  try {
    final added = await player.addToQueue(song);
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(added ? '已设为下一首播放' : '当前歌曲已在播放中')));
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加失败：$error')));
    }
  }
}

class _SongActionTile extends StatelessWidget {
  const _SongActionTile({required this.action});

  final SongSheetAction action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = action.danger ? colorScheme.error : colorScheme.onSurface;
    return ListTile(
      leading: Icon(action.icon, color: color),
      title: Text(action.title, style: TextStyle(color: color)),
      subtitle: action.subtitle == null ? null : Text(action.subtitle!),
      onTap: () {
        Navigator.of(context).pop();
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => action.onTap(),
        );
      },
    );
  }
}
