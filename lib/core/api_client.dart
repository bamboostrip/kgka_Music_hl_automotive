import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? token;
  String? t1;

  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) {
    return _send(
      () => _client.get(AppConfig.apiUri(path, query), headers: _headers),
    );
  }

  Future<dynamic> post(
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
  }) {
    return _send(
      () => _client.post(
        AppConfig.apiUri(path, query),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (token case final value?) {
      headers['Authorization'] = 'Bearer $value';
      headers['token'] = value;
    }
    if (t1 case final value?) {
      headers['t1'] = value;
    }

    return headers;
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final response = await request();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.body, statusCode: response.statusCode);
    }

    if (response.body.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      return unwrapData(decoded);
    } on FormatException {
      return response.body;
    }
  }

  void close() => _client.close();
}

dynamic unwrapData(dynamic json) {
  if (json is Map<String, dynamic>) {
    final data = json['data'];
    if (data != null) {
      return data;
    }
  }
  return json;
}
