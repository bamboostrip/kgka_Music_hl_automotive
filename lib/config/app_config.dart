class AppConfig {
  const AppConfig._();

  static const appName = 'KA Music';

  static const apiBaseUrl = String.fromEnvironment(
    'KA_MUSIC_API_BASE_URL',
    defaultValue: 'https://music.api.hoilai.cn',
  );

  static const debugLyrics = bool.fromEnvironment(
    'KA_MUSIC_DEBUG_LYRICS',
    defaultValue: true,
  );

  static Uri apiUri(String path, [Map<String, Object?> query = const {}]) {
    final base = Uri.parse(apiBaseUrl);
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final normalizedBasePath = base.path.endsWith('/')
        ? base.path
        : '${base.path}/';

    return base.replace(
      path: '$normalizedBasePath$cleanPath',
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value != null && entry.value.toString().isNotEmpty)
            entry.key: entry.value.toString(),
      },
    );
  }
}
