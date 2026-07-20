import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../src/rust/api.dart';
import '../src/rust/frb_generated.dart';
import 'api_client.dart';

class RustApiClient {
  RustApiClient._(this._engine);

  static RustApiClient? _instance;
  final Engine _engine;

  String? token;
  String? t1;
  String? sessionId;

  static Future<RustApiClient> getInstance() async {
    if (_instance != null) return _instance!;
    await RustLib.init();
    final dir = await getApplicationSupportDirectory();
    final engine = await createEngine(dataDir: dir.path);
    _instance = RustApiClient._(engine);
    return _instance!;
  }

  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) {
    return _request('GET', path, query, null);
  }

  Future<dynamic> getRaw(Uri uri) async {
    final client = http.Client();
    try {
      final response = await client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(response.body, statusCode: response.statusCode);
      }
      if (response.body.trim().isEmpty) return null;
      return jsonDecode(response.body);
    } finally {
      client.close();
    }
  }

  Future<dynamic> post(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
  }) {
    return _request('POST', path, query, body);
  }

  Future<dynamic> _request(
    String method,
    String path,
    Map<String, Object?> query,
    Map<String, Object?>? body,
  ) async {
    final queryJson = jsonEncode(
      query.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
    final bodyJson = body != null ? jsonEncode(body) : null;

    try {
      final result = await engineRequest(
        engine: _engine,
        method: method,
        path: path,
        query: queryJson,
        body: bodyJson,
      );
      if (result.isEmpty || result == 'null') return null;
      final decoded = jsonDecode(result);
      return unwrapData(decoded);
    } catch (e) {
      throw ApiException(e.toString(), statusCode: 500);
    }
  }

  void setSession(String? userid, String? token, String? t1) {
    this.token = token;
    this.t1 = t1;
    engineSetSession(
      engine: _engine,
      userid: userid ?? '',
      token: token ?? '',
      t1: t1 ?? '',
    );
  }

  void close() {}
}
