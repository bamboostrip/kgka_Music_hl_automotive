class LoginSession {
  const LoginSession({this.userId, this.token, this.t1});

  final String? userId;
  final String? token;
  final String? t1;

  bool get isValid => token != null && token!.isNotEmpty;

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

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUrl,
    this.songCount,
    this.playCount,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final int? songCount;
  final int? playCount;

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

  factory PlaylistSummary.fromUser(Map<String, dynamic> json) {
    return PlaylistSummary(
      id:
          asString(json['global_collection_id']) ??
          asString(json['listid']) ??
          '',
      title: asString(json['name']) ?? '我的歌单',
      subtitle: asString(json['list_create_username']),
      coverUrl: normalizeImageUrl(asString(json['pic'])),
      songCount: asInt(json['count']),
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
    );
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

  factory Song.fromDaily(Map<String, dynamic> json) {
    final songId = asString(json['songid']) ?? asString(json['audio_id']);
    return Song(
      id: asString(json['mixsongid']) ?? songId ?? asString(json['hash']) ?? '',
      title:
          asString(json['songname']) ?? asString(json['audio_name']) ?? '未知歌曲',
      artist: asString(json['author_name']) ?? '未知艺人',
      hash:
          asString(json['hash']) ??
          asString(json['hash_320']) ??
          asString(json['hash_flac']) ??
          '',
      albumId: asString(json['album_id']),
      albumAudioId: songId,
      albumName: asString(json['album_name']),
      coverUrl: normalizeImageUrl(asString(json['sizable_cover'])),
      duration: durationFromSeconds(json['time_length']),
    );
  }

  factory Song.fromPlaylist(Map<String, dynamic> json) {
    final singers = json['singerinfo'];
    final artist = singers is List && singers.isNotEmpty
        ? singers
              .whereType<Map<String, dynamic>>()
              .map(
                (item) =>
                    asString(item['name']) ?? asString(item['author_name']),
              )
              .whereType<String>()
              .join(' / ')
        : null;
    final albumInfo = json['albuminfo'];
    final albumMap = albumInfo is Map<String, dynamic> ? albumInfo : null;

    return Song(
      id: asString(json['fileid']) ?? asString(json['hash']) ?? '',
      title: asString(json['name']) ?? asString(json['audio_name']) ?? '未知歌曲',
      artist: artist?.isNotEmpty == true ? artist! : '未知艺人',
      hash: asString(json['hash']) ?? '',
      albumId: asString(json['album_id']) ?? asString(albumMap?['album_id']),
      albumAudioId:
          asString(json['album_audio_id']) ?? asString(json['audio_id']),
      albumName:
          asString(albumMap?['album_name']) ?? asString(json['album_name']),
      coverUrl: normalizeImageUrl(
        asString(json['cover']) ??
            asString(albumMap?['sizable_cover']) ??
            asString(albumMap?['cover']),
      ),
      duration: durationFromMilliseconds(json['timelen']),
    );
  }
}

class PlaylistDetail {
  const PlaylistDetail({required this.info, required this.songs});

  final PlaylistSummary info;
  final List<Song> songs;
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
    this.words = const [],
  });

  final Duration time;
  final String text;
  final Duration? duration;
  final String? translation;
  final List<LyricWord> words;

  LyricLine copyWith({String? translation}) {
    return LyricLine(
      time: time,
      text: text,
      duration: duration,
      translation: translation ?? this.translation,
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
