abstract class ApiClientInterface {
  String? token;
  String? t1;
  String? sessionId;

  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]);
  Future<dynamic> getRaw(Uri uri);
  Future<dynamic> post(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
  });
  void close();
}
