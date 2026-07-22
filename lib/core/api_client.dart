class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
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
