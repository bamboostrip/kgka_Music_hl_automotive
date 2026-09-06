part of 'music_api.dart';

/// 歌单域：我的歌单 / 推荐歌单 / 相似歌单 / 歌单详情与曲目管理 / 外部歌单解析。
mixin _MusicApiPlaylist on _MusicApiBase {
  Future<List<PlaylistSummary>> userPlaylists({
    int page = 1,
    int pageSize = 30,
  }) async {
    final json = asMap(
      await _client.get('/user/playlist', {'page': page, 'pagesize': pageSize}),
    );
    final currentUserId = asString(json['userid']);
    final rawItems = asList(json['info']).whereType<Map<String, dynamic>>();
    final playlists = rawItems
        .map(
          (item) =>
              PlaylistSummary.fromUser(item, currentUserId: currentUserId),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
    return _orderUserPlaylistsForDisplay(playlists);
  }

  Future<List<PlaylistSummary>> recommendedPlaylists({
    int categoryId = 0,
    int page = 1,
  }) async {
    final json = asMap(
      await _client.get('/top/playlist', {
        'category_id': categoryId,
        'page': page,
      }),
    );
    return asList(json['special_list'])
        .whereType<Map<String, dynamic>>()
        .map(PlaylistSummary.fromRecommend)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  /// 获取相似歌单。
  Future<List<PlaylistSummary>> similarPlaylists(String ids) async {
    final raw = await _client.get('/playlist/similar', {'ids': ids});
    final json = asMap(raw);
    final groups = (raw is List ? raw : asList(json['data']))
        .whereType<Map<String, dynamic>>()
        .toList();
    final items = groups.isEmpty
        ? const <Map<String, dynamic>>[]
        : asList(
            groups.first['collection_list'],
          ).whereType<Map<String, dynamic>>();
    return items
        .map(PlaylistSummary.fromSimilar)
        .where((playlist) => playlist.id.isNotEmpty)
        .toList();
  }

  Future<PlaylistSummary> playlistInfo(String id) async {
    final json = asMap(await _client.get('/playlist/detail', {'ids': id}));
    return PlaylistSummary.fromDetail(json);
  }

  Future<List<Song>> playlistSongs(
    String id, {
    int page = 1,
    int pageSize = 80,
    bool fetchAll = false,
  }) async {
    if (!fetchAll) {
      final songPage = await playlistSongPage(
        id,
        page: page,
        pageSize: pageSize,
      );
      return songPage.songs;
    }

    final allSongs = <Song>[];
    var currentPage = 1;
    const perPage = 200;
    // 与 rankAudioAll 同构：某页 rawItemCount 不足一页即终止；并设防御页数
    // 上限，防止上游异常数据（永远满页）导致死循环。不提前按"过滤后为空"
    // break：满页全是无 hash 下架歌曲时 rawItemCount 仍满页，提前 break 会
    // 截断列表；空页 rawItemCount 为 0 同样能正确终止。
    const maxPages = 30;
    while (currentPage <= maxPages) {
      final songPage = await playlistSongPage(
        id,
        page: currentPage,
        pageSize: perPage,
      );
      allSongs.addAll(songPage.songs);
      if (songPage.rawItemCount < perPage) break;
      currentPage++;
    }
    return allSongs;
  }

  Future<SongPage> playlistSongPage(
    String id, {
    int page = 1,
    int pageSize = 80,
  }) async {
    final json = asMap(
      await _client.get('/playlist/track/all', {
        'id': id,
        'page': page,
        'pagesize': pageSize,
      }),
    );
    final items = asList(json['songs']);
    // 无 hash（下架/无版权等）不展示；rawItemCount 仍用接口条数判断分页
    final songs = items
        .whereType<Map<String, dynamic>>()
        .map(Song.fromPlaylist)
        .where((song) => song.hash.isNotEmpty)
        .toList();
    return SongPage(songs: songs, rawItemCount: items.length);
  }

  Future<PlaylistDetail> playlistDetail(String id) async {
    final results = await Future.wait([
      playlistInfo(id),
      playlistSongs(id, pageSize: 50),
    ]);
    return PlaylistDetail(
      info: results[0] as PlaylistSummary,
      songs: results[1] as List<Song>,
    );
  }

  /// 解析网易云 / QQ 音乐歌单分享链接，返回歌单名和歌曲名称列表。
  Future<ExternalPlaylistParseResult> parseExternalPlaylist(
    String sourceText,
  ) async {
    final json = asMap(
      await _client.post(
        '/playlist/external/parse',
        body: {'sourceText': sourceText},
      ),
    );
    return ExternalPlaylistParseResult.fromJson(json);
  }

  Future<void> createPlaylist(String name, {bool private = false}) async {
    await _client.post(
      '/playlist/create',
      query: {'name': name, 'type': private ? 1 : 0},
    );
  }

  Future<void> collectPlaylist({
    required String name,
    required String globalCollectionId,
  }) async {
    await _client.post(
      '/playlist/add',
      query: {'name': name, 'list_create_gid': globalCollectionId},
    );
  }

  Future<void> deletePlaylist(String listId) async {
    await _client.post('/playlist/del', query: {'listid': listId});
  }

  Future<Map<String, dynamic>?> addToPlaylist(String listId, Song song) {
    return addSongsToPlaylist(listId, [song]);
  }

  Future<Map<String, dynamic>?> addSongsToPlaylist(
    String listId,
    List<Song> songs,
  ) async {
    if (songs.isEmpty) return null;
    final result = await _client.post(
      '/playlist/tracks/add',
      body: {'listId': listId, 'songs': songs.map(_songAddPayload).toList()},
    );
    return result is Map<String, dynamic> ? result : null;
  }

  Future<Map<String, dynamic>?> removeFromPlaylist(String listId, Song song) {
    return removeSongsFromPlaylist(listId, [song]);
  }

  Future<Map<String, dynamic>?> removeSongsFromPlaylist(
    String listId,
    List<Song> songs, {
    List<int>? fileIds,
  }) async {
    final ids =
        fileIds ??
        songs
            .map((song) => int.tryParse(song.id) ?? 0)
            .where((id) => id != 0)
            .toList();
    if (ids.isEmpty) return null;
    final result = await _client.post(
      '/playlist/tracks/del',
      query: {'listid': listId, 'fileids': ids.join(',')},
    );
    return result is Map<String, dynamic> ? result : null;
  }

  Map<String, Object?> _songAddPayload(Song song) {
    return {
      'name': song.title,
      'hash': song.hash,
      'albumId': song.albumId,
      'mixSongId': song.albumAudioId ?? song.id,
    };
  }
}

List<PlaylistSummary> _orderUserPlaylistsForDisplay(
  List<PlaylistSummary> playlists,
) {
  if (playlists.length <= 2) {
    return playlists;
  }
  return [...playlists.take(2), ...playlists.skip(2).toList().reversed];
}
