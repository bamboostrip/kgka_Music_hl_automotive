class LoginSession {
  const LoginSession({this.userId, this.token, this.t1, this.sessionId});

  final String? userId;
  final String? token;
  final String? t1;
  final String? sessionId;

  bool get isValid =>
      (token != null && token!.isNotEmpty) ||
      (sessionId != null && sessionId!.isNotEmpty);

  factory LoginSession.fromJson(Map<String, dynamic> json) {
    return LoginSession(
      userId: asString(json['userid']),
      token: asString(json['token']),
      t1: asString(json['t1']),
    );
  }
}

class UserProfile {
  const UserProfile({required this.nickname, this.avatarUrl});

  final String nickname;
  final String? avatarUrl;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      nickname: asString(json['nickname']) ?? 'KA Music 用户',
      avatarUrl: normalizeImageUrl(asString(json['pic'])),
    );
  }
}

class VipReceiveItem {
  const VipReceiveItem({this.day, this.receiveVip, this.vipType});

  final String? day;
  final int? receiveVip;
  final String? vipType;

  factory VipReceiveItem.fromJson(Map<String, dynamic> json) {
    return VipReceiveItem(
      day: asString(json['day']),
      receiveVip: asInt(json['receive_vip']),
      vipType: asString(json['vip_type']),
    );
  }
}

class VipReceiveHistory {
  const VipReceiveHistory({
    this.month,
    this.serverTime,
    this.items = const [],
    this.status,
    this.errorCode,
  });

  final String? month;
  final int? serverTime;
  final List<VipReceiveItem> items;
  final int? status;
  final int? errorCode;

  factory VipReceiveHistory.fromJson(Map<String, dynamic> json) {
    return VipReceiveHistory(
      month: asString(json['month']),
      serverTime: asInt(json['server_time']),
      items: asList(json['list'])
          .whereType<Map>()
          .map((item) => VipReceiveItem.fromJson(asMap(item)))
          .toList(),
      status: asInt(json['status']),
      errorCode: asInt(json['error_code']),
    );
  }
}

class OneDayVipResult {
  const OneDayVipResult({this.status, this.errorCode});

  final int? status;
  final int? errorCode;

  factory OneDayVipResult.fromJson(Map<String, dynamic> json) {
    return OneDayVipResult(
      status: asInt(json['status']),
      errorCode: asInt(json['error_code']),
    );
  }
}

class UpgradeVipResult {
  const UpgradeVipResult({this.status, this.errorCode});

  final int? status;
  final int? errorCode;

  factory UpgradeVipResult.fromJson(Map<String, dynamic> json) {
    return UpgradeVipResult(
      status: asInt(json['status']),
      errorCode: asInt(json['error_code']),
    );
  }
}

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUrl,
    this.songCount,
    this.playCount,
    this.isDefault,
    this.creatorName,
    this.creatorUserId,
    this.currentUserId,
    this.sourceGlobalId,
    this.sourceListId,
    this.type,
    this.source,
    this.listId,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final int? songCount;
  final int? playCount;
  final int? isDefault;
  final String? creatorName;
  final String? creatorUserId;
  final String? currentUserId;
  final String? sourceGlobalId;
  final String? sourceListId;

  /// API `type` field: 0 = 用户创建, 1 = 收藏的歌单
  final int? type;

  /// API `source` field: 1 = 自建, 2 = 来自音乐库
  final int? source;

  /// Raw numeric playlist ID for track add/remove operations
  final String? listId;

  bool get isLikedPlaylist => isDefault == 2 || title.trim() == '我喜欢';

  bool get isCreatedPlaylist {
    if (type == 0) {
      return true;
    }
    if (type == 1) {
      return false;
    }
    if (isDefault == 0 || isDefault == 1) {
      return true;
    }
    return currentUserId != null &&
        creatorUserId != null &&
        currentUserId == creatorUserId;
  }

  bool get hasCollectionSource {
    return (sourceGlobalId != null && sourceGlobalId!.isNotEmpty) ||
        (sourceListId != null && sourceListId!.isNotEmpty);
  }

  factory PlaylistSummary.fromRecommend(Map<String, dynamic> json) {
    return PlaylistSummary(
      id:
          asString(json['global_collection_id']) ??
          asString(json['specialid']) ??
          '',
      title: asString(json['specialname']) ?? '未命名歌单',
      subtitle: asString(json['nickname']) ?? asString(json['intro']),
      coverUrl: normalizeImageUrl(asString(json['flexible_cover'])),
      playCount: asInt(json['play_count']),
    );
  }

  factory PlaylistSummary.fromUser(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final creatorName = asString(json['list_create_username']);
    return PlaylistSummary(
      id:
          asString(json['global_collection_id']) ??
          asString(json['listid']) ??
          '',
      title: asString(json['name']) ?? '我的歌单',
      subtitle: creatorName,
      coverUrl: normalizeImageUrl(asString(json['pic'])),
      songCount: asInt(json['count']),
      isDefault: asInt(json['is_def']) ?? asInt(json['is_default']),
      creatorName: creatorName,
      creatorUserId: asString(json['list_create_userid']),
      currentUserId: currentUserId,
      sourceGlobalId: asString(json['list_create_gid']),
      sourceListId: asString(json['list_create_listid']),
      type: asInt(json['type']),
      source: asInt(json['source']),
      listId: asString(json['listid']),
    );
  }

  factory PlaylistSummary.fromDetail(Map<String, dynamic> json) {
    return PlaylistSummary(
      id:
          asString(json['global_collection_id']) ??
          asString(json['listid']) ??
          '',
      title: asString(json['name']) ?? '歌单',
      subtitle:
          asString(json['list_create_username']) ?? asString(json['intro']),
      coverUrl: normalizeImageUrl(asString(json['pic'])),
      songCount: asInt(json['count']),
      playCount: asInt(json['heat']),
      creatorName: asString(json['list_create_username']),
      creatorUserId: asString(json['list_create_userid']),
      sourceGlobalId: asString(json['list_create_gid']),
      sourceListId: asString(json['list_create_listid']),
    );
  }

  factory PlaylistSummary.fromCache(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: asString(json['id']) ?? '',
      title: asString(json['title']) ?? '我的歌单',
      subtitle: asString(json['subtitle']),
      coverUrl: asString(json['coverUrl']),
      songCount: asInt(json['songCount']),
      playCount: asInt(json['playCount']),
      isDefault: asInt(json['isDefault']),
      creatorName: asString(json['creatorName']),
      creatorUserId: asString(json['creatorUserId']),
      currentUserId: asString(json['currentUserId']),
      sourceGlobalId: asString(json['sourceGlobalId']),
      sourceListId: asString(json['sourceListId']),
      type: asInt(json['type']),
      source: asInt(json['source']),
      listId: asString(json['listId']),
    );
  }

  Map<String, dynamic> toCache() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'coverUrl': coverUrl,
      'songCount': songCount,
      'playCount': playCount,
      'isDefault': isDefault,
      'creatorName': creatorName,
      'creatorUserId': creatorUserId,
      'currentUserId': currentUserId,
      'sourceGlobalId': sourceGlobalId,
      'sourceListId': sourceListId,
      'type': type,
      'source': source,
      'listId': listId,
    };
  }
}

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.hash,
    this.albumId,
    this.albumAudioId,
    this.albumName,
    this.coverUrl,
    this.duration,
    this.artists = const [],
  });

  final String id;
  final String title;
  final String artist;
  final String hash;
  final String? albumId;
  final String? albumAudioId;
  final String? albumName;
  final String? coverUrl;
  final Duration? duration;
  final List<ArtistRef> artists;

  factory Song.fromSearch(Map<String, dynamic> json) {
    final songId =
        asString(json['MixSongID']) ??
        asString(json['mixsongid']) ??
        asString(json['songid']) ??
        asString(json['audio_id']) ??
        asString(json['fileid']);

    final hash =
        asString(json['FileHash']) ??
        asString(json['hash']) ??
        asString(json['hash_320']) ??
        asString(json['hash_flac']) ??
        '';
    final imageUrl =
        asString(json['Image']) ??
        asString(json['sizable_cover']) ??
        asString(json['img']);
    final artists = parseArtists(
      json,
      fallbackName:
          asString(json['SingerName']) ??
          asString(json['author_name']) ??
          asString(json['singername']) ??
          asString(json['singer_name']),
    );
    final artistName = artists.map((artist) => artist.name).join(' / ');

    return Song(
      id: songId ?? hash,
      title:
          asString(json['FileName']) ??
          asString(json['songname']) ??
          asString(json['name']) ??
          asString(json['audio_name']) ??
          '未知歌曲',
      artist: artistName.isNotEmpty
          ? artistName
          : asString(json['SingerName']) ??
                asString(json['author_name']) ??
                asString(json['singername']) ??
                asString(json['singer_name']) ??
                '未知艺人',
      hash: hash,
      albumId: asString(json['AlbumID']) ?? asString(json['album_id']),
      albumAudioId: songId,
      albumName: asString(json['AlbumName']) ?? asString(json['album_name']),
      coverUrl: normalizeImageUrl(imageUrl),
      artists: artists,
      duration:
          durationFromSeconds(json['Duration']) ??
          durationFromMilliseconds(json['timelen']) ??
          durationFromSeconds(json['time_length']) ??
          durationFromSeconds(json['duration']),
    );
  }

  factory Song.fromDaily(Map<String, dynamic> json) {
    final songId = asString(json['songid']) ?? asString(json['audio_id']);
    final artists = parseArtists(
      json,
      fallbackName: asString(json['author_name']),
    );
    final artistName = artists.map((artist) => artist.name).join(' / ');
    return Song(
      id: asString(json['mixsongid']) ?? songId ?? asString(json['hash']) ?? '',
      title:
          asString(json['songname']) ?? asString(json['audio_name']) ?? '未知歌曲',
      artist: artistName.isNotEmpty
          ? artistName
          : asString(json['author_name']) ?? '未知艺人',
      hash:
          asString(json['hash']) ??
          asString(json['hash_320']) ??
          asString(json['hash_flac']) ??
          '',
      albumId: asString(json['album_id']),
      albumAudioId: asString(json['mixsongid']) ?? songId,
      albumName: asString(json['album_name']),
      coverUrl: normalizeImageUrl(asString(json['sizable_cover'])),
      artists: artists,
      duration: durationFromSeconds(json['time_length']),
    );
  }

  factory Song.fromPlaylist(Map<String, dynamic> json) {
    final artists = parseArtists(json);
    final artist = artists.map((artist) => artist.name).join(' / ');
    final albumInfo = json['albuminfo'];
    final albumMap = albumInfo is Map<String, dynamic> ? albumInfo : null;

    return Song(
      id: asString(json['fileid']) ?? asString(json['hash']) ?? '',
      title: asString(json['name']) ?? asString(json['audio_name']) ?? '未知歌曲',
      artist: artist.isNotEmpty ? artist : '未知艺人',
      hash: asString(json['hash']) ?? '',
      albumId: asString(json['album_id']) ?? asString(albumMap?['album_id']),
      albumAudioId:
          asString(json['mixsongid']) ??
          asString(json['album_audio_id']) ??
          asString(json['audio_id']),
      albumName:
          asString(albumMap?['album_name']) ?? asString(json['album_name']),
      coverUrl: normalizeImageUrl(
        asString(json['cover']) ??
            asString(albumMap?['sizable_cover']) ??
            asString(albumMap?['cover']),
      ),
      artists: artists,
      duration: durationFromMilliseconds(json['timelen']),
    );
  }

  factory Song.fromArtistAudio(Map<String, dynamic> json, {String? artistId}) {
    var artists = parseArtists(
      json,
      fallbackName: asString(json['author_name']),
    );
    final authorName = asString(json['author_name']);
    if (artistId != null &&
        artistId.isNotEmpty &&
        authorName != null &&
        artists.every((artist) => artist.id.isEmpty)) {
      artists = [ArtistRef(id: artistId, name: authorName)];
    }
    final artistName = artists.map((artist) => artist.name).join(' / ');
    final transParam = asMap(json['trans_param']);

    return Song(
      id:
          asString(json['album_audio_id']) ??
          asString(json['audio_id']) ??
          asString(json['hash']) ??
          '',
      title: asString(json['audio_name']) ?? asString(json['name']) ?? '未知歌曲',
      artist: artistName.isNotEmpty ? artistName : authorName ?? '未知艺人',
      hash: asString(json['hash']) ?? '',
      albumId: asString(json['album_id']),
      albumAudioId: asString(json['album_audio_id']),
      albumName: asString(json['album_name']),
      coverUrl: normalizeImageUrl(
        asString(transParam['union_cover']) ??
            asString(json['sizable_cover']) ??
            asString(json['cover']),
      ),
      artists: artists,
      duration:
          durationFromMilliseconds(json['timelength']) ??
          durationFromMilliseconds(json['timelen']),
    );
  }
}

class PlaylistDetail {
  const PlaylistDetail({required this.info, required this.songs});

  final PlaylistSummary info;
  final List<Song> songs;
}

class ArtistRef {
  const ArtistRef({required this.id, required this.name, this.avatarUrl});

  final String id;
  final String name;
  final String? avatarUrl;
}

class ArtistDetail {
  const ArtistDetail({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.birthday,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String? birthday;

  factory ArtistDetail.fromJson(
    Map<String, dynamic> json, {
    required String id,
  }) {
    return ArtistDetail(
      id: id,
      name: asString(json['author_name']) ?? '未知歌手',
      avatarUrl: normalizeImageUrl(
        asString(json['sizable_avatar']) ?? asString(json['avatar']),
      ),
      birthday: asString(json['birthday']),
    );
  }
}

List<ArtistRef> parseArtists(
  Map<String, dynamic> json, {
  String? fallbackName,
}) {
  final artists = <ArtistRef>[];
  void addFromMap(Map<String, dynamic> item) {
    final id =
        asString(item['id']) ??
        asString(item['author_id']) ??
        asString(item['AuthorID']) ??
        asString(item['AuthorId']) ??
        asString(item['singerid']) ??
        asString(item['singer_id']) ??
        asString(item['SingerId']) ??
        asString(item['SingerID']);
    final name =
        asString(item['name']) ??
        asString(item['author_name']) ??
        asString(item['SingerName']) ??
        asString(item['singername']) ??
        asString(item['singer_name']);
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return;
    }
    if (artists.any((artist) => artist.id == id)) {
      return;
    }
    artists.add(
      ArtistRef(
        id: id,
        name: name,
        avatarUrl: normalizeImageUrl(
          asString(item['sizable_avatar']) ?? asString(item['avatar']),
        ),
      ),
    );
  }

  for (final key in const ['singerinfo', 'authors', 'author', 'singers']) {
    final value = json[key];
    if (value is List) {
      for (final item in value.whereType<Map<String, dynamic>>()) {
        addFromMap(item);
      }
    } else if (value is Map<String, dynamic>) {
      addFromMap(value);
    }
  }

  addFromMap(json);

  if (artists.isEmpty && fallbackName != null && fallbackName.isNotEmpty) {
    final names = fallbackName
        .split(RegExp(r'\s*(?:/|、|,|，|&)\s*'))
        .where((name) => name.trim().isNotEmpty);
    for (final name in names) {
      artists.add(ArtistRef(id: '', name: name.trim()));
    }
  }
  return artists;
}

class DailyRecommend {
  const DailyRecommend({
    required this.title,
    this.subtitle,
    this.coverUrl,
    required this.songs,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;
  final List<Song> songs;

  factory DailyRecommend.fromJson(Map<String, dynamic> json) {
    final date = asString(json['creation_date']);
    return DailyRecommend(
      title: date == null ? '每日推荐' : '每日推荐 $date',
      subtitle: asString(json['sub_title']),
      coverUrl: normalizeImageUrl(asString(json['cover_img_url'])),
      songs: asList(json['song_list'])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromDaily)
          .where((song) => song.hash.isNotEmpty)
          .toList(),
    );
  }
}

class PlayUrl {
  const PlayUrl({required this.url, required this.hash});

  final String url;
  final String hash;

  factory PlayUrl.fromJson(Map<String, dynamic> json) {
    final urls = asList(json['url']).whereType<String>().toList();
    return PlayUrl(
      url: urls.isNotEmpty ? urls.first : '',
      hash: asString(json['hash']) ?? '',
    );
  }
}

class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
    this.duration,
    this.translation,
    this.romanization,
    this.words = const [],
  });

  final Duration time;
  final String text;
  final Duration? duration;
  final String? translation;
  final String? romanization;
  final List<LyricWord> words;

  LyricLine copyWith({String? translation, String? romanization}) {
    return LyricLine(
      time: time,
      text: text,
      duration: duration,
      translation: translation ?? this.translation,
      romanization: romanization ?? this.romanization,
      words: words,
    );
  }

  int activeWordIndex(Duration position) {
    if (words.isEmpty) {
      return -1;
    }
    var active = -1;
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      if (position >= word.time) {
        active = index;
      } else {
        break;
      }
    }
    return active;
  }
}

class LyricWord {
  const LyricWord({
    required this.time,
    required this.duration,
    required this.text,
  });

  final Duration time;
  final Duration duration;
  final String text;
}

class CommentLikeInfo {
  const CommentLikeInfo({this.count, this.haslike, this.likenum});

  final int? count;
  final bool? haslike;
  final int? likenum;

  factory CommentLikeInfo.fromJson(Map<String, dynamic> json) {
    return CommentLikeInfo(
      count: asInt(json['count']),
      haslike: json['haslike'] is bool ? json['haslike'] : null,
      likenum: asInt(json['likenum']),
    );
  }
}

class CommentVipInfo {
  const CommentVipInfo({this.vipType, this.mType, this.userType});

  final int? vipType;
  final int? mType;
  final int? userType;

  factory CommentVipInfo.fromJson(Map<String, dynamic> json) {
    return CommentVipInfo(
      vipType: asInt(json['vip_type']),
      mType: asInt(json['m_type']),
      userType: asInt(json['user_type']),
    );
  }
}

class CommentImage {
  const CommentImage({this.url, this.width, this.height});

  final String? url;
  final int? width;
  final int? height;

  factory CommentImage.fromJson(Map<String, dynamic> json) {
    return CommentImage(
      url: normalizeImageUrl(asString(json['url'])),
      width: asInt(json['width']),
      height: asInt(json['height']),
    );
  }
}

class CommentUserDetail {
  const CommentUserDetail({
    this.medalType,
    this.medalRollWord,
    this.wordV3,
    this.pendantName,
    this.pendantUrl,
  });

  final String? medalType;
  final String? medalRollWord;
  final String? wordV3;
  final String? pendantName;
  final String? pendantUrl;

  factory CommentUserDetail.fromJson(Map<String, dynamic> json) {
    return CommentUserDetail(
      medalType: asString(json['medal_type']),
      medalRollWord: asString(json['medal_roll_word']),
      wordV3: asString(json['word_v3']),
      pendantName: asString(json['pendant_name']),
      pendantUrl: normalizeImageUrl(asString(json['pendant_url'])),
    );
  }
}

class CommentTailInfo {
  const CommentTailInfo({this.id, this.name});

  final String? id;
  final String? name;

  factory CommentTailInfo.fromJson(Map<String, dynamic> json) {
    return CommentTailInfo(
      id: asString(json['id']),
      name: asString(json['name']),
    );
  }
}

class CommentHotWord {
  const CommentHotWord({this.content, this.count});

  final String? content;
  final int? count;

  factory CommentHotWord.fromJson(Map<String, dynamic> json) {
    return CommentHotWord(
      content: asString(json['content']),
      count: asInt(json['count']),
    );
  }
}

class CommentClassifyItem {
  const CommentClassifyItem({this.id, this.label, this.icon, this.cnt});

  final int? id;
  final String? label;
  final String? icon;
  final int? cnt;

  factory CommentClassifyItem.fromJson(Map<String, dynamic> json) {
    return CommentClassifyItem(
      id: asInt(json['id']),
      label: asString(json['label']),
      icon: asString(json['icon']),
      cnt: asInt(json['cnt']),
    );
  }
}

class CommentTag {
  const CommentTag({this.name, this.type, this.count});

  final String? name;
  final String? type;
  final int? count;

  factory CommentTag.fromJson(Map<String, dynamic> json) {
    return CommentTag(
      name: asString(json['name']),
      type: asString(json['type']),
      count: asInt(json['count']),
    );
  }
}

class CommentConfig {
  const CommentConfig({this.emptyTip, this.inputHint});

  final String? emptyTip;
  final String? inputHint;

  factory CommentConfig.fromJson(Map<String, dynamic> json) {
    return CommentConfig(
      emptyTip: asString(json['emptyTip']),
      inputHint: asString(json['input_hint']),
    );
  }
}

class CommentSongScore {
  const CommentSongScore({this.scoreUserCount, this.songScore});

  final int? scoreUserCount;
  final double? songScore;

  factory CommentSongScore.fromJson(Map<String, dynamic> json) {
    return CommentSongScore(
      scoreUserCount: asInt(json['score_user_count']),
      songScore: (json['song_score'] is num)
          ? (json['song_score'] as num).toDouble()
          : double.tryParse(asString(json['song_score']) ?? ''),
    );
  }
}

class MusicCommentItem {
  const MusicCommentItem({
    required this.id,
    this.content,
    this.addtime,
    this.replyNum,
    this.userId,
    this.userName,
    this.userPic,
    this.userSex,
    this.like,
    this.images,
    this.location,
    this.hash,
    this.score,
    this.vipinfo,
    this.udetail,
    this.machineTail,
    this.tail,
  });

  final int id;
  final String? content;
  final String? addtime;
  final int? replyNum;
  final int? userId;
  final String? userName;
  final String? userPic;
  final int? userSex;
  final CommentLikeInfo? like;
  final List<CommentImage>? images;
  final String? location;
  final String? hash;
  final int? score;
  final CommentVipInfo? vipinfo;
  final CommentUserDetail? udetail;
  final String? machineTail;
  final CommentTailInfo? tail;

  factory MusicCommentItem.fromJson(Map<String, dynamic> json) {
    return MusicCommentItem(
      id: asInt(json['id']) ?? 0,
      content: asString(json['content']),
      addtime: asString(json['addtime']),
      replyNum: asInt(json['reply_num']),
      userId: asInt(json['user_id']),
      userName: asString(json['user_name']),
      userPic: normalizeImageUrl(asString(json['user_pic'])),
      userSex: asInt(json['user_sex']),
      like: json['like'] is Map
          ? CommentLikeInfo.fromJson(asMap(json['like']))
          : null,
      images: json['images'] is List
          ? asList(json['images'])
                .whereType<Map>()
                .map((e) => CommentImage.fromJson(asMap(e)))
                .toList()
          : null,
      location: asString(json['location']),
      hash: asString(json['hash']),
      score: asInt(json['score']),
      vipinfo: json['vipinfo'] is Map
          ? CommentVipInfo.fromJson(asMap(json['vipinfo']))
          : null,
      udetail: json['udetail'] is Map
          ? CommentUserDetail.fromJson(asMap(json['udetail']))
          : null,
      machineTail: asString(json['machine_tail']),
      tail: json['tail'] is Map
          ? CommentTailInfo.fromJson(asMap(json['tail']))
          : null,
    );
  }
}

class MusicCommentResponse {
  const MusicCommentResponse({
    this.msg,
    this.message,
    this.childrenid,
    this.count,
    this.combineCount,
    this.currentPage,
    this.maxPage,
    this.list,
    this.hotWordList,
    this.classifyList,
    this.tag,
    this.config,
    this.songScore,
    this.status,
    this.errorCode,
  });

  final String? msg;
  final String? message;
  final String? childrenid;
  final int? count;
  final int? combineCount;
  final int? currentPage;
  final int? maxPage;
  final List<MusicCommentItem>? list;
  final List<CommentHotWord>? hotWordList;
  final List<CommentClassifyItem>? classifyList;
  final List<CommentTag>? tag;
  final CommentConfig? config;
  final CommentSongScore? songScore;
  final int? status;
  final int? errorCode;

  factory MusicCommentResponse.fromJson(Map<String, dynamic> json) {
    return MusicCommentResponse(
      msg: asString(json['msg']),
      message: asString(json['message']),
      childrenid: asString(json['childrenid']),
      count: asInt(json['count']),
      combineCount: asInt(json['combine_count']),
      currentPage: asInt(json['current_page']),
      maxPage: asInt(json['maxPage']),
      list: json['list'] is List
          ? asList(json['list'])
                .whereType<Map>()
                .map((e) => MusicCommentItem.fromJson(asMap(e)))
                .toList()
          : null,
      hotWordList: json['hot_word_list'] is List
          ? asList(json['hot_word_list'])
                .whereType<Map>()
                .map((e) => CommentHotWord.fromJson(asMap(e)))
                .toList()
          : null,
      classifyList: json['classify_list'] is List
          ? asList(json['classify_list'])
                .whereType<Map>()
                .map((e) => CommentClassifyItem.fromJson(asMap(e)))
                .toList()
          : null,
      tag: json['tag'] is List
          ? asList(json['tag'])
                .whereType<Map>()
                .map((e) => CommentTag.fromJson(asMap(e)))
                .toList()
          : null,
      config: json['config'] is Map
          ? CommentConfig.fromJson(asMap(json['config']))
          : null,
      songScore: json['song_score'] is Map
          ? CommentSongScore.fromJson(asMap(json['song_score']))
          : null,
      status: asInt(json['status']),
      errorCode: asInt(json['error_code']),
    );
  }
}

class SearchHotKeyword {
  const SearchHotKeyword({required this.keyword, this.reason});

  final String keyword;
  final String? reason;

  factory SearchHotKeyword.fromJson(Map<String, dynamic> json) {
    return SearchHotKeyword(
      keyword: asString(json['keyword']) ?? '',
      reason: asString(json['reason']),
    );
  }
}

class SearchHotCategory {
  const SearchHotCategory({required this.name, required this.keywords});

  final String name;
  final List<SearchHotKeyword> keywords;

  factory SearchHotCategory.fromJson(Map<String, dynamic> json) {
    return SearchHotCategory(
      name: asString(json['name']) ?? '',
      keywords: asList(json['keywords'])
          .whereType<Map<String, dynamic>>()
          .map(SearchHotKeyword.fromJson)
          .toList(),
    );
  }
}

String? asString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? asInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  return int.tryParse(value.toString());
}

List<dynamic> asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

Duration? durationFromSeconds(Object? value) {
  final seconds = asInt(value);
  return seconds == null ? null : Duration(seconds: seconds);
}

Duration? durationFromMilliseconds(Object? value) {
  final milliseconds = asInt(value);
  return milliseconds == null ? null : Duration(milliseconds: milliseconds);
}

String? normalizeImageUrl(String? url, {int size = 480}) {
  if (url == null) {
    return null;
  }
  return url
      .replaceAll('{size}', '$size')
      .replaceAll('{SIZE}', '$size')
      .replaceAll('/{size}/', '/$size/')
      .replaceAll('/{SIZE}/', '/$size/');
}

String formatDuration(Duration? duration) {
  if (duration == null) {
    return '--:--';
  }
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
