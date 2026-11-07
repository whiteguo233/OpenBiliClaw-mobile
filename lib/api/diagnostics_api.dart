import 'client.dart';

/// Reads the backend's existing anomaly feed, including source recoveries.
class DiagnosticsApi {
  DiagnosticsApi(this.client);
  final ApiClient client;

  Future<Map<String, dynamic>> list({int limit = 100}) async {
    final data = await client.get(
      '/diagnostics/alerts?limit=$limit',
      timeout: 15,
    );
    if (data['alerts'] is! List) {
      throw const FormatException('异常记录响应不完整');
    }
    return data;
  }
}
