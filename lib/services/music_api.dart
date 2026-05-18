import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../core/api_client.dart';
import '../models/music_models.dart';

class MusicApi {
  MusicApi(this._client);

  final ApiClient _client;

  void setSession(LoginSession? session) {
    _client.token = session?.token;
    _client.t1 = session?.t1;
    _client.sessionId = session?.sessionId;
  }

  Future<void> sendLoginCode(String mobile) async {
    await _client.post('/captcha/sent', query: {'mobile': mobile});
  }

  Future<LoginSession> loginWithPhone({
    required String mobile,
    required String code,
  }) async {
    final json = asMap(
      await _client.post(
        '/login/cellphone',
        body: {'mobile': mobile, 'code': code},
      ),
    );
    final session = LoginSession.fromJson(json);
    return LoginSession(
      userId: session.userId,
      token: session.token,
      t1: session.t1,
      sessionId: _client.sessionId,
    );
  }

  Future<LoginSession> refreshToken() async {
    final json = asMap(await _client.post('/login/token'));
    final session = LoginSession.fromJson(json);
    return LoginSession(
      userId: session.userId,
      token: session.token,
      t1: session.t1,
      sessionId: _client.sessionId,
    );
  }

  Future<void> logout() async {
    await _client.post('/login/logout');
  }

  Future<UserProfile> userDetail() async {
    final json = asMap(await _client.get('/user/detail'));
    return UserProfile.fromJson(json);
  }

  Future<List<PlaylistSummary>> userPlaylists({
    int page = 1,
    int pageSize = 30,
  }) async {
    final json = asMap(
      await _client.get('/user/playlist', {'page': page, 'pagesize': pageSize}),
    );
    _debugPlaylistLogObject('raw response', json);
    final currentUserId = asString(json['userid']);
    final rawItems = asList(json['info']).whereType<Map<String, dynamic>>();
    _debugPlaylistLogObject(
      'raw item fields',
      rawItems
          .map(
            (item) => {
              'name': item['name'],
              'listid': item['listid'],
              'global_collection_id': item['global_collection_id'],
              'count': item['count'],
              'is_def': item['is_def'],
              'is_default': item['is_default'],
              'type': item['type'],
              'userid': item['userid'],
              'list_create_username': item['list_create_username'],
              'list_create_userid': item['list_create_userid'],
              'list_create_gid': item['list_create_gid'],
              'list_create_listid': item['list_create_listid'],
            },
          )
          .toList(),
    );
    final playlists = rawItems
        .map(
          (item) =>
              PlaylistSummary.fromUser(item, currentUserId: currentUserId),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
    final orderedPlaylists = _orderUserPlaylistsForDisplay(playlists);
    _debugPlaylistLogObject(
      'parsed item fields',
      orderedPlaylists
          .map(
            (item) => {
              'title': item.title,
              'id': item.id,
              'songCount': item.songCount,
              'isDefault': item.isDefault,
              'type': item.type,
              'source': item.source,
              'isLikedPlaylist': item.isLikedPlaylist,
              'isCreatedPlaylist': item.isCreatedPlaylist,
              'creatorName': item.creatorName,
              'creatorUserId': item.creatorUserId,
              'currentUserId': item.currentUserId,
              'sourceGlobalId': item.sourceGlobalId,
              'sourceListId': item.sourceListId,
              'hasCollectionSource': item.hasCollectionSource,
            },
          )
          .toList(),
    );
    return orderedPlaylists;
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

  Future<DailyRecommend> dailyRecommend() async {
    final json = asMap(await _client.get('/recommend/songs'));
    return DailyRecommend.fromJson(json);
  }

  Future<void> dailyVip() async {
    await _client.get('/youth/day/vip');
  }

  Future<void> addListeningTime() async {
    await _client.post('/listen/timeadd');
  }

  Future<ArtistDetail> artistDetail(String id) async {
    final json = asMap(await _client.get('/artist/detail', {'id': id}));
    return ArtistDetail.fromJson(json, id: id);
  }

  Future<List<Song>> artistAudios(
    String id, {
    int page = 1,
    int pageSize = 30,
    String sort = 'hot',
  }) async {
    final raw = await _client.get('/artist/audios', {
      'id': id,
      'page': page,
      'pagesize': pageSize,
      'sort': sort,
    });
    _debugArtistLogObject('/artist/audios raw', raw);

    final json = asMap(raw);
    final items = raw is List
        ? raw
        : asList(
            json['data'] ??
                json['songs'] ??
                json['song'] ??
                json['list'] ??
                json['info'] ??
                _firstListValue(json),
          );
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) => Song.fromArtistAudio(item, artistId: id))
        .where((song) => song.hash.isNotEmpty)
        .toList();
  }

  Object? _firstListValue(Map<String, dynamic> json) {
    for (final value in json.values) {
      if (value is List) {
        return value;
      }
      if (value is Map) {
        final nested = _firstListValue(asMap(value));
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  Future<MusicCommentResponse> musicComments(
    String mixsongid, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final json = asMap(
      await _client.get('/comment/music', {
        'mixsongid': mixsongid,
        'page': page,
        'pagesize': pageSize,
      }),
    );
    return MusicCommentResponse.fromJson(json);
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
      final json = asMap(
        await _client.get('/playlist/track/all', {
          'id': id,
          'page': page,
          'pagesize': pageSize,
        }),
      );
      return asList(json['songs'])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromPlaylist)
          .where((song) => song.hash.isNotEmpty)
          .toList();
    }

    final allSongs = <Song>[];
    var currentPage = 1;
    const perPage = 200;
    while (true) {
      final json = asMap(
        await _client.get('/playlist/track/all', {
          'id': id,
          'page': currentPage,
          'pagesize': perPage,
        }),
      );
      final songs = asList(json['songs'])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromPlaylist)
          .where((song) => song.hash.isNotEmpty)
          .toList();
      if (songs.isEmpty) break;
      allSongs.addAll(songs);
      if (songs.length < perPage) break;
      currentPage++;
    }
    return allSongs;
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

  Future<PlayUrl> songUrl(Song song) async {
    final json = asMap(
      await _client.get('/song/url', {
        'hash': song.hash,
        'quality': '128',
        'album_id': song.albumId,
        'album_audio_id': song.albumAudioId,
        'free_part': false,
      }),
    );
    return PlayUrl.fromJson(json);
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

  Future<void> addToPlaylist(String listId, Song song) async {
    await addSongsToPlaylist(listId, [song]);
  }

  Future<void> addSongsToPlaylist(String listId, List<Song> songs) async {
    if (songs.isEmpty) return;
    await _client.post(
      '/playlist/tracks/add',
      body: {'listId': listId, 'songs': songs.map(_songAddPayload).toList()},
    );
  }

  Future<void> removeFromPlaylist(String listId, Song song) async {
    await removeSongsFromPlaylist(listId, [song]);
  }

  Future<void> removeSongsFromPlaylist(String listId, List<Song> songs) async {
    final fileIds = songs
        .map((song) => song.id)
        .where((id) => id.isNotEmpty)
        .join(',');
    if (fileIds.isEmpty) return;
    await _client.post(
      '/playlist/tracks/del',
      query: {'listid': listId, 'fileids': fileIds},
    );
  }

  Map<String, Object?> _songAddPayload(Song song) {
    return {
      'name': song.title,
      'hash': song.hash,
      'albumId': song.albumId,
      'mixSongId': song.albumAudioId ?? song.id,
    };
  }

  Future<List<SearchHotCategory>> searchHotKeywords() async {
    final json = asMap(await _client.get('/search/hot'));
    return asList(json['list'])
        .whereType<Map<String, dynamic>>()
        .map(SearchHotCategory.fromJson)
        .toList();
  }

  Future<List<String>> searchSuggest(String keywords) async {
    final json = asMap(
      await _client.get('/search/suggest', {'keywords': keywords}),
    );
    final items = asList(json['music']);
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) => asString(item['keyword']) ?? '')
        .where((k) => k.isNotEmpty)
        .toList();
  }

  Future<List<Song>> searchSongs(
    String keywords, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final raw = await _client.get('/search', {
      'keywords': keywords,
      'page': page,
      'pagesize': pageSize,
      'type': 'song',
    });
    if (kDebugMode) {
      debugPrint('[KA Music][search] keywords="$keywords"');
      debugPrint('[KA Music][search] raw type: ${raw.runtimeType}');
      if (raw is List) {
        debugPrint('[KA Music][search] list length: ${raw.length}');
      } else if (raw is Map) {
        debugPrint('[KA Music][search] map keys: ${raw.keys.toList()}');
      }
    }
    // API returns either a plain array or { songs: [...] }
    final List songs;
    if (raw is List) {
      songs = raw;
    } else {
      final json = asMap(raw);
      songs = asList(json['songs'] ?? json['song'] ?? json['lists']);
    }
    return songs
        .whereType<Map<String, dynamic>>()
        .map(Song.fromSearch)
        .where((song) => song.hash.isNotEmpty)
        .toList();
  }

  Future<List<LyricLine>> lyrics(Song song) async {
    _debugLyricLog(
      'request song="${song.title}" artist="${song.artist}" hash="${song.hash}" albumAudioId="${song.albumAudioId}"',
    );
    final candidate = await _searchLyricCandidate(song);
    _debugLyricLogObject('selected candidate', candidate);
    if (candidate == null) {
      _debugLyricLog('no lyric candidate found');
      return const [];
    }

    final krcLyrics = await _lyricByFormat(candidate, 'krc');
    if (krcLyrics.isNotEmpty) {
      return krcLyrics;
    }

    return _lyricByFormat(candidate, 'lrc');
  }

  Future<Map<String, dynamic>?> _searchLyricCandidate(Song song) async {
    final query = {'hash': song.hash};
    _debugLyricLogObject('search query', query);
    final searchJson = await _client.get('/search/lyric', query);
    _debugLyricLogObject('search response', searchJson);

    final candidate = _findLyricCandidate(searchJson);
    if (candidate != null) {
      _debugLyricLog('search found candidate by hash');
      return candidate;
    }
    return null;
  }

  Future<List<LyricLine>> _lyricByFormat(
    Map<String, dynamic> candidate,
    String format,
  ) async {
    final id =
        asString(candidate['id']) ??
        asString(candidate['lyrics_id']) ??
        asString(candidate['lyric_id']) ??
        asString(candidate['lyricid']);
    final accessKey =
        asString(candidate['accesskey']) ??
        asString(candidate['access_key']) ??
        asString(candidate['accessKey']);
    if (id == null || accessKey == null) {
      return const [];
    }

    final result = asMap(
      await _client.get('/lyric', {
        'id': id,
        'accesskey': accessKey,
        'fmt': format,
        'decode': true,
      }),
    );
    _debugLyricLogObject('$format lyric response keys', result.keys.toList());

    final translationContent = asString(result['decodedTranslation']);
    final candidates = [
      asString(result['decodedContent']),
      asString(result['rawContent']),
      asString(result['content']),
    ].whereType<String>().toList();
    _debugLyricLog('$format content candidate count=${candidates.length}');

    candidates.sort(
      (a, b) => _lyricContentScore(b).compareTo(_lyricContentScore(a)),
    );
    for (var index = 0; index < candidates.length; index++) {
      final content = candidates[index];
      _debugLyricContent(
        '$format content[$index] score=${_lyricContentScore(content)} length=${content.length}',
        content,
      );
      if (translationContent != null) {
        _debugLyricContent(
          '$format decodedTranslation length=${translationContent.length}',
          translationContent,
        );
      }
      final lines = parseLyrics(
        content,
        translationContent: translationContent,
      );
      _debugLyricLog('$format content[$index] parsed lines=${lines.length}');
      if (lines.isNotEmpty) {
        return lines;
      }
    }
    _debugLyricLog('$format lyric parsed no lines');
    return const [];
  }

  Map<String, dynamic>? _findLyricCandidate(Object? value) {
    final root = asMap(value);
    final direct = _asLyricCandidate(root);
    if (direct != null) {
      return direct;
    }

    final candidates = [
      root['candidates'],
      root['candidate'],
      root['list'],
      root['lyrics'],
      root['items'],
      root['info'],
      root['data'],
    ];

    for (final candidate in candidates) {
      if (candidate is List && candidate.isNotEmpty) {
        for (final item in candidate) {
          final found = _findLyricCandidate(item);
          if (found != null) {
            return found;
          }
        }
      }
      if (candidate is Map) {
        final found = _findLyricCandidate(candidate);
        if (found != null) {
          return found;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _asLyricCandidate(Map<String, dynamic> value) {
    final hasId =
        asString(value['id']) != null ||
        asString(value['lyrics_id']) != null ||
        asString(value['lyric_id']) != null ||
        asString(value['lyricid']) != null;
    final hasAccessKey =
        asString(value['accesskey']) != null ||
        asString(value['access_key']) != null ||
        asString(value['accessKey']) != null;
    return hasId && hasAccessKey ? value : null;
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

List<LyricLine> parseLyrics(String? content, {String? translationContent}) {
  if (content == null || content.trim().isEmpty) {
    return const [];
  }

  final normalized = content
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n');
  final krcLines = _parseKrc(normalized);
  final parsed = krcLines.isNotEmpty ? krcLines : _parseLrc(normalized);
  if (parsed.isEmpty) {
    return const [];
  }

  final variants = _parseLyricVariants(
    translationContent: translationContent,
    originalContent: normalized,
  );
  return _mergeLyricVariants(parsed, variants);
}

List<LyricLine> _parseKrc(String content) {
  final lines = <LyricLine>[];
  final offset = _extractOffset(content);
  final lineExpression = RegExp(r'^\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\](.*)$');
  final wordExpression = RegExp(r'<\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*>');

  for (final rawLine in content.split('\n')) {
    final match = lineExpression.firstMatch(rawLine.trim());
    if (match == null) {
      continue;
    }

    final start = int.tryParse(match.group(1) ?? '');
    final duration = int.tryParse(match.group(2) ?? '');
    if (start == null || duration == null) {
      continue;
    }

    final content = match.group(3) ?? '';
    final words = <LyricWord>[];
    final matches = wordExpression.allMatches(content).toList();
    for (var index = 0; index < matches.length; index++) {
      final wordMatch = matches[index];
      final wordStart = int.tryParse(wordMatch.group(1) ?? '') ?? 0;
      final wordDuration = int.tryParse(wordMatch.group(2) ?? '') ?? 0;
      final wordEnd = index + 1 < matches.length
          ? matches[index + 1].start
          : content.length;
      final wordText = content.substring(wordMatch.end, wordEnd);
      if (wordText.isEmpty) {
        continue;
      }
      words.add(
        LyricWord(
          time: Duration(
            milliseconds: (start + wordStart + offset)
                .clamp(0, 1 << 31)
                .toInt(),
          ),
          duration: Duration(
            milliseconds: wordDuration.clamp(0, 1 << 31).toInt(),
          ),
          text: wordText,
        ),
      );
    }

    final displayWords = _trimLyricWords(words);
    final text = displayWords.isEmpty
        ? content.replaceAll(wordExpression, '').trim()
        : displayWords.map((word) => word.text).join();
    if (text.isEmpty) {
      continue;
    }

    lines.add(
      LyricLine(
        time: Duration(
          milliseconds: (start + offset).clamp(0, 1 << 31).toInt(),
        ),
        duration: Duration(milliseconds: duration.clamp(0, 1 << 31).toInt()),
        text: text,
        words: displayWords,
      ),
    );
  }

  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

List<LyricWord> _trimLyricWords(List<LyricWord> words) {
  final result = words
      .map(
        (word) => LyricWord(
          time: word.time,
          duration: word.duration,
          text: word.text,
        ),
      )
      .toList();
  while (result.isNotEmpty && result.first.text.trim().isEmpty) {
    result.removeAt(0);
  }
  while (result.isNotEmpty && result.last.text.trim().isEmpty) {
    result.removeLast();
  }
  if (result.isEmpty) {
    return result;
  }
  result[0] = LyricWord(
    time: result[0].time,
    duration: result[0].duration,
    text: result[0].text.trimLeft(),
  );
  final lastIndex = result.length - 1;
  result[lastIndex] = LyricWord(
    time: result[lastIndex].time,
    duration: result[lastIndex].duration,
    text: result[lastIndex].text.trimRight(),
  );
  return result.where((word) => word.text.isNotEmpty).toList();
}

List<LyricLine> _parseLrc(String content) {
  final lines = <LyricLine>[];
  final offset = _extractOffset(content);
  final expression = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  for (final rawLine in content.split('\n')) {
    final matches = expression.allMatches(rawLine).toList();
    if (matches.isEmpty) {
      continue;
    }
    final text = rawLine.replaceAll(expression, '').trim();
    if (text.isEmpty) {
      continue;
    }
    for (final match in matches) {
      final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
      final fraction = match.group(3) ?? '0';
      final milliseconds = fraction.length == 3
          ? int.parse(fraction)
          : int.parse(fraction.padRight(3, '0'));
      lines.add(
        LyricLine(
          time: Duration(
            milliseconds:
                (Duration(
                          minutes: minutes,
                          seconds: seconds,
                          milliseconds: milliseconds,
                        ).inMilliseconds +
                        offset)
                    .clamp(0, 1 << 31)
                    .toInt(),
          ),
          text: text,
        ),
      );
    }
  }

  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

int _extractOffset(String content) {
  final match = RegExp(
    r'^\[offset:([+-]?\d+)\]',
    multiLine: true,
  ).firstMatch(content);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

int _lyricContentScore(String content) {
  var score = 0;
  if (RegExp(
    r'^\[\s*-?\d+\s*,\s*-?\d+\s*\].*<',
    multiLine: true,
  ).hasMatch(content)) {
    score += 100;
  }
  if (RegExp(
    r'^\[\s*-?\d+\s*,\s*-?\d+\s*\]',
    multiLine: true,
  ).hasMatch(content)) {
    score += 60;
  }
  if (RegExp(r'\[\d{1,2}:\d{1,2}').hasMatch(content)) {
    score += 40;
  }
  if (content.contains('[language:')) {
    score += 10;
  }
  return score;
}

_ParsedLyricVariants _parseLyricVariants({
  required String? translationContent,
  required String originalContent,
}) {
  final decodedTranslation = _parseTimedVariant(translationContent);
  final krcVariants = _parseKrcLanguageVariants(originalContent);
  return _ParsedLyricVariants(
    translation: !decodedTranslation.isEmpty
        ? decodedTranslation
        : krcVariants.translation,
    romanization: krcVariants.romanization,
  );
}

_TimedLyricVariant _parseTimedVariant(String? content) {
  final lines = parseLyrics(content);
  return _TimedLyricVariant(
    byTime: {
      for (final line in lines)
        if (line.text.isNotEmpty) line.time.inMilliseconds: line.text,
    },
  );
}

_ParsedLyricVariants _parseKrcLanguageVariants(String content) {
  final match = RegExp(
    r'^\[language:([A-Za-z0-9+/=]+)\]',
    multiLine: true,
  ).firstMatch(content);
  final encoded = match?.group(1);
  if (encoded == null || encoded.isEmpty) {
    return const _ParsedLyricVariants();
  }

  try {
    final decoded = utf8.decode(base64.decode(encoded));
    final json = jsonDecode(decoded);
    final translationByTime = <int, String>{};
    final translationByIndex = <String>[];
    final romanizationByTime = <int, String>{};
    final romanizationByIndex = <String>[];
    _collectKrcLanguageRows(
      json,
      translationByTime: translationByTime,
      translationByIndex: translationByIndex,
      romanizationByTime: romanizationByTime,
      romanizationByIndex: romanizationByIndex,
    );
    return _ParsedLyricVariants(
      translation: _TimedLyricVariant(
        byTime: translationByTime,
        byIndex: translationByIndex,
      ),
      romanization: _TimedLyricVariant(
        byTime: romanizationByTime,
        byIndex: romanizationByIndex,
      ),
    );
  } catch (_) {
    return const _ParsedLyricVariants();
  }
}

void _collectKrcLanguageRows(
  Object? value, {
  required Map<int, String> translationByTime,
  required List<String> translationByIndex,
  required Map<int, String> romanizationByTime,
  required List<String> romanizationByIndex,
}) {
  if (value is List) {
    for (final item in value) {
      _collectKrcLanguageRows(
        item,
        translationByTime: translationByTime,
        translationByIndex: translationByIndex,
        romanizationByTime: romanizationByTime,
        romanizationByIndex: romanizationByIndex,
      );
    }
    return;
  }
  if (value is! Map) {
    return;
  }

  final map = asMap(value);
  final sectionType = asInt(map['type']);
  final lyricContent = map['lyricContent'];
  if (lyricContent is List) {
    for (final row in lyricContent) {
      final parsedRow = _parseKrcLanguageRow(row, sectionType);
      if (parsedRow == null) {
        continue;
      }

      final byTime = sectionType == 0 ? romanizationByTime : translationByTime;
      final byIndex = sectionType == 0
          ? romanizationByIndex
          : translationByIndex;

      if (parsedRow.time != null) {
        byTime[parsedRow.time!] = parsedRow.text;
      } else {
        byIndex.add(parsedRow.text);
      }
    }
  }

  for (final child in map.values) {
    if (child is List || child is Map) {
      _collectKrcLanguageRows(
        child,
        translationByTime: translationByTime,
        translationByIndex: translationByIndex,
        romanizationByTime: romanizationByTime,
        romanizationByIndex: romanizationByIndex,
      );
    }
  }
}

({int? time, String text})? _parseKrcLanguageRow(
  Object? row,
  int? sectionType,
) {
  if (row is! List || row.isEmpty) {
    return null;
  }

  final time = row.length > 1 ? asInt(row[0]) : null;
  final values = row.map(asString).whereType<String>().toList();
  if (values.isEmpty) {
    return null;
  }

  final text = time != null && row.length > 1
      ? asString(row[1])
      : (sectionType == 0 ? values.join('') : values.join(' ').trim());
  if (text == null || text.isEmpty) {
    return null;
  }
  return (time: time, text: text);
}

List<LyricLine> _mergeLyricVariants(
  List<LyricLine> lines,
  _ParsedLyricVariants variants,
) {
  if (variants.isEmpty) {
    return lines;
  }

  final merged = <LyricLine>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    merged.add(
      line.copyWith(
        translation:
            variants.translation.byTime[line.time.inMilliseconds] ??
            _nearestLyricVariant(
              line.time.inMilliseconds,
              variants.translation.byTime,
            ) ??
            (index < variants.translation.byIndex.length
                ? variants.translation.byIndex[index]
                : null),
        romanization:
            variants.romanization.byTime[line.time.inMilliseconds] ??
            _nearestLyricVariant(
              line.time.inMilliseconds,
              variants.romanization.byTime,
            ) ??
            (index < variants.romanization.byIndex.length
                ? variants.romanization.byIndex[index]
                : null),
      ),
    );
  }
  return merged;
}

String? _nearestLyricVariant(int time, Map<int, String> variants) {
  var bestDistance = 1 << 31;
  String? bestText;
  for (final entry in variants.entries) {
    final distance = (entry.key - time).abs();
    if (distance < bestDistance && distance <= 250) {
      bestDistance = distance;
      bestText = entry.value;
    }
  }
  return bestText;
}

class _ParsedLyricVariants {
  const _ParsedLyricVariants({
    this.translation = const _TimedLyricVariant(),
    this.romanization = const _TimedLyricVariant(),
  });

  final _TimedLyricVariant translation;
  final _TimedLyricVariant romanization;

  bool get isEmpty => translation.isEmpty && romanization.isEmpty;
}

class _TimedLyricVariant {
  const _TimedLyricVariant({this.byTime = const {}, this.byIndex = const []});

  final Map<int, String> byTime;
  final List<String> byIndex;

  bool get isEmpty => byTime.isEmpty && byIndex.isEmpty;
}

void _debugLyricLog(String message) {
  if (!AppConfig.debugLyrics || !kDebugMode) {
    return;
  }
  debugPrint('[KA Music][lyrics] $message');
}

void _debugLyricLogObject(String label, Object? value) {
  if (!AppConfig.debugLyrics || !kDebugMode) {
    return;
  }
  final text = const JsonEncoder.withIndent('  ').convert(value);
  _debugLyricContent(label, text);
}

void _debugLyricContent(String label, String content) {
  if (!AppConfig.debugLyrics || !kDebugMode) {
    return;
  }
  debugPrint('[KA Music][lyrics] ==== $label ====');
  const chunkSize = 1800;
  for (var start = 0; start < content.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, content.length);
    debugPrint(content.substring(start, end));
  }
  debugPrint('[KA Music][lyrics] ==== end $label ====');
}

void _debugPlaylistLogObject(String label, Object? value) {
  if (!kDebugMode) {
    return;
  }
  final text = const JsonEncoder.withIndent('  ').convert(value);
  debugPrint('[KA Music][playlists] ==== $label ====');
  const chunkSize = 1800;
  for (var start = 0; start < text.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, text.length);
    debugPrint(text.substring(start, end));
  }
  debugPrint('[KA Music][playlists] ==== end $label ====');
}

void _debugArtistLogObject(String label, Object? value) {
  if (!kDebugMode) {
    return;
  }
  final text = const JsonEncoder.withIndent('  ').convert(value);
  debugPrint('[KA Music][artist] ==== $label ====');
  const chunkSize = 1800;
  for (var start = 0; start < text.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, text.length);
    debugPrint(text.substring(start, end));
  }
  debugPrint('[KA Music][artist] ==== end $label ====');
}
