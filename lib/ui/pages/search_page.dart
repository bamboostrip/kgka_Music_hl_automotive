import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../widgets/artwork.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<String> _hotKeywords = const [];
  List<String> _suggestions = const [];
  List<Song> _results = const [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _loadHotKeywords();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHotKeywords() async {
    try {
      final keywords = await widget.api.searchHotKeywords();
      if (mounted) setState(() => _hotKeywords = keywords);
    } catch (_) {}
  }

  void _onTextChanged() {
    _debounce?.cancel();
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _suggestions = const [];
        _results = const [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(text);
    });
  }

  Future<void> _fetchSuggestions(String keywords) async {
    try {
      final suggestions = await widget.api.searchSuggest(keywords);
      if (mounted && _controller.text.trim() == keywords) {
        setState(() => _suggestions = suggestions);
      }
    } catch (_) {}
  }

  Future<void> _search(String keywords) async {
    if (keywords.isEmpty) return;
    _debounce?.cancel();
    setState(() {
      _loading = true;
      _suggestions = const [];
      _searched = true;
    });
    try {
      final songs = await widget.api.searchSongs(keywords);
      if (mounted) setState(() => _results = songs);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSubmit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) _search(text);
  }

  void _onKeywordTap(String keyword) {
    _controller.text = keyword;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: keyword.length),
    );
    _search(keyword);
  }

  void _playSong(Song song) {
    widget.player.playSong(song, queue: _results);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 4,
        title: Container(
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: .54),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _onSubmit(),
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        _focusNode.requestFocus();
                      },
                    )
                  : null,
              hintText: '搜索歌曲，歌手',
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '取消',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.auth,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final text = _controller.text.trim();

    if (_searched && text.isNotEmpty) {
      return _results.isEmpty
          ? _EmptyResults(keyword: text)
          : _SearchResults(
              songs: _results,
              onPlay: _playSong,
              isLiked: (song) => widget.auth.isLiked(song),
              onLikeTap: (song) => widget.auth.toggleLike(song),
              auth: widget.auth,
            );
    }

    if (text.isEmpty) {
      return _HotKeywords(
        keywords: _hotKeywords,
        onTap: _onKeywordTap,
      );
    }

    if (_suggestions.isNotEmpty) {
      return _SuggestionList(
        suggestions: _suggestions,
        onTap: _onKeywordTap,
      );
    }

    return const SizedBox.shrink();
  }
}

class _HotKeywords extends StatelessWidget {
  const _HotKeywords({required this.keywords, required this.onTap});

  final List<String> keywords;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (keywords.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 160),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            '热门搜索',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final keyword in keywords)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onTap(keyword),
                child: Ink(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: .64,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    keyword,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onTap});

  final List<String> suggestions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 160),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 62,
        color: colorScheme.outlineVariant.withValues(alpha: .4),
      ),
      itemBuilder: (context, index) {
        final keyword = suggestions[index];
        return ListTile(
          leading: Icon(
            Icons.search_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          title: Text(
            keyword,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => onTap(keyword),
        );
      },
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.songs,
    required this.onPlay,
    required this.isLiked,
    required this.onLikeTap,
    required this.auth,
  });

  final List<Song> songs;
  final void Function(Song song) onPlay;
  final bool Function(Song song) isLiked;
  final void Function(Song song) onLikeTap;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 160),
          itemCount: songs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            final song = songs[index];
            final liked = isLiked(song);
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onPlay(song),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Artwork(url: song.coverUrl, size: 58, borderRadius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () => onLikeTap(song),
                      icon: Icon(
                        liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: liked ? Colors.redAccent : colorScheme.outline,
                        size: 27,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.keyword});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 160),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: colorScheme.primary.withValues(alpha: .64),
          ),
          const SizedBox(height: 14),
          Text(
            '没有找到「$keyword」相关歌曲',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '换个关键词试试',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
