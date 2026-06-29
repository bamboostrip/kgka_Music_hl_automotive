import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../adaptive_layout.dart';
import '../../controllers/player_controller.dart';
import '../../controllers/local_music_controller.dart';
import '../widgets/toast.dart';
import '../widgets/artwork.dart';
import '../widgets/now_playing_badge.dart';

class LocalSongsPage extends StatefulWidget {
  const LocalSongsPage({
    super.key,
    required this.player,
    required this.localMusic,
  });

  final PlayerController player;
  final LocalMusicController localMusic;

  @override
  State<LocalSongsPage> createState() => _LocalSongsPageState();
}

class _LocalSongsPageState extends State<LocalSongsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _selectOrClearDir() async {
    final localMusic = widget.localMusic;
    final dir = localMusic.localMusicDir;
    if (dir == null || dir.isEmpty) {
      await _pickLocalMusicDir();
      return;
    }

    final option = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '当前目录: $dir',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('选择新目录'),
                onTap: () => Navigator.of(context).pop(1),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                title: Text('清除目录', style: TextStyle(color: colorScheme.error)),
                onTap: () => Navigator.of(context).pop(2),
              ),
            ],
          ),
        );
      },
    );

    if (option == 1) {
      await _pickLocalMusicDir();
    } else if (option == 2) {
      await localMusic.setLocalMusicDir(null);
      Toast.success('已清除本地目录');
    }
  }

  Future<void> _pickLocalMusicDir() async {
    try {
      final path = await FilePicker.getDirectoryPath();
      if (path == null) return;
      await widget.localMusic.setLocalMusicDir(path);
      Toast.success('设置成功并开始扫描');
    } catch (e) {
      debugPrint('Error picking folder: $e');
      Toast.error('选择文件夹失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地音乐'),
        actions: [
          IconButton(
            tooltip: '修改目录',
            onPressed: _selectOrClearDir,
            icon: const Icon(Icons.folder_open_rounded),
          ),
          AnimatedBuilder(
            animation: widget.localMusic,
            builder: (context, _) {
              if (widget.localMusic.isScanning) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return IconButton(
                tooltip: '重新扫描',
                onPressed: widget.localMusic.localMusicDir == null
                    ? null
                    : () async {
                        await widget.localMusic.scanLocalMusic();
                        Toast.success('扫描完成');
                      },
                icon: const Icon(Icons.refresh_rounded),
              );
            },
          ),
        ],
      ),
      body: AdaptiveContentPadding(
        child: AnimatedBuilder(
          animation: Listenable.merge([widget.localMusic, widget.player]),
          builder: (context, _) {
          final dir = widget.localMusic.localMusicDir;
          if (dir == null || dir.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.computer_rounded,
                      size: 72,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '未设置本地音乐目录',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '将扫描指定目录下的音频文件并自动加载同目录下的 `.lrc` 歌词',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _selectOrClearDir,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('设置目录'),
                    ),
                  ],
                ),
              ),
            );
          }

          final allSongs = widget.localMusic.songs;
          final filteredSongs = allSongs.where((song) {
            final titleMatch = song.title.toLowerCase().contains(_searchQuery);
            final artistMatch = song.artist.toLowerCase().contains(_searchQuery);
            return titleMatch || artistMatch;
          }).toList();

          return Column(
            children: [
              // Path display card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_rounded, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dir,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '共 ${allSongs.length} 首',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Search bar
              if (allSongs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '检索本地音乐...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () => _searchController.clear(),
                              icon: const Icon(Icons.clear_rounded),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
              // Songs list
              Expanded(
                child: widget.localMusic.isScanning
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : filteredSongs.isEmpty
                        ? Center(
                            child: Text(
                              allSongs.isEmpty ? '目录下没有找到可播放的音频文件' : '没有检索到匹配的歌曲',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: filteredSongs.length,
                            itemBuilder: (context, index) {
                              final song = filteredSongs[index];
                              final isCurrent = widget.player.currentSong?.hash == song.hash;
                              final isPlaying = isCurrent && widget.player.isPlaying;

                              return ListTile(
                                leading: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Stack(
                                    children: [
                                      const Artwork(url: null, size: 44),
                                      if (isCurrent)
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: NowPlayingBadge(
                                              active: true,
                                              playing: isPlaying,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent ? colorScheme.primary.withValues(alpha: .7) : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                onTap: () {
                                  widget.player.playSong(song, queue: filteredSongs);
                                },
                              );
                            },
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
