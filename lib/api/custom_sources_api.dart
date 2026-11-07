import 'dart:typed_data';

import 'client.dart';

/// Native access to the same source policy and Ego session used by web clients.
/// All requests use the configured backend, session cookie and Tailnet transport.
class CustomSourcesApi {
  CustomSourcesApi(this.client);
  final ApiClient client;
  static String id(String value) => Uri.encodeComponent(value);
  String draftPath(String draftId) => '/custom-sources/drafts/${id(draftId)}';
  Future<List<Map<String, dynamic>>> attention() async {
    final data = await client.get('/custom-sources/attention', timeout: 15);
    if (data['items'] is! List) {
      throw const FormatException('来源提醒响应不完整');
    }
    return sourceMaps(data['items']);
  }

  Future<Map<String, dynamic>> list() async {
    final data = await client.get('/custom-sources', timeout: 30);
    if (data['items'] is! List || data['executors'] is! List) {
      throw const FormatException('来源列表响应不完整，请重试');
    }
    return data;
  }

  Future<Map<String, dynamic>> update(
    String sourceId,
    Map<String, dynamic> values,
  ) => client.patch('/custom-sources/${id(sourceId)}', body: values);
  Future<void> archive(String sourceId) async {
    await client.delete('/custom-sources/${id(sourceId)}');
  }

  Future<Map<String, dynamic>> runs(String sourceId) =>
      client.get('/custom-sources/${id(sourceId)}/runs');
  Future<Map<String, dynamic>> login(String sourceId) =>
      client.post('/custom-sources/${id(sourceId)}/login', timeout: 30);
  Future<Map<String, dynamic>> draft(String draftId) =>
      client.get(draftPath(draftId));
  Future<Map<String, dynamic>> takeover(String draftId, {String origin = ''}) =>
      client.post(
        '${draftPath(draftId)}/takeover',
        body: {if (origin.isNotEmpty) 'login_origin': origin},
        timeout: 120,
      );
  Future<Uint8List> screenshot(String draftId) =>
      client.getBytes(client.apiUri('${draftPath(draftId)}/screenshot'));
  Future<Map<String, dynamic>> action(
    String draftId,
    Map<String, dynamic> action,
  ) => client.post('${draftPath(draftId)}/action', body: action, timeout: 45);
  Future<void> closeLogin(String draftId) async {
    await client.post('${draftPath(draftId)}/close', body: {}, timeout: 15);
  }

  Future<Map<String, dynamic>> resume(String draftId) =>
      client.post('${draftPath(draftId)}/resume', body: {}, timeout: 180);
  Future<Map<String, dynamic>> prepareEgo() => client.post(
    '/custom-sources/executors/ego/prepare',
    body: {},
    timeout: 30,
  );

  /// Only interpret a backend-owned takeover link, never send cookies to it.
  /// Native UI calls draft APIs instead of loading a webpage or passing tokens.
  String? loginDraftId(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        (uri.hasScheme && !['http', 'https'].contains(uri.scheme))) {
      return null;
    }
    final backend = Uri.parse(client.baseUrl);
    if (uri.hasAuthority &&
        (uri.host != backend.host ||
            uri.port != backend.port ||
            (uri.hasScheme && uri.scheme != backend.scheme))) {
      return null;
    }
    final prefix = client.basePath.isEmpty ? '' : '/${client.basePath}';
    if (![
      '/web/source-login.html',
      '/m/desktop/source-login.html',
      '$prefix/web/source-login.html',
      '$prefix/m/desktop/source-login.html',
    ].contains(uri.path)) {
      return null;
    }
    final value = uri.queryParameters['draft_id']?.trim() ?? '';
    return value.isEmpty ? null : value;
  }
}

List<Map<String, dynamic>> sourceMaps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
    : [];
String sourceStatus(dynamic value) =>
    const {
      'ok': '正常',
      'ready': '已就绪',
      'disabled': '已停用',
      'needs_login': '需要登录或验证',
      'login_required': '需要登录或验证',
      'failed': '失败',
      'degraded': '异常',
      'rate_limited': '网站限流，等待重试',
      'running': '正在采集',
      'empty': '暂无内容',
      'not_modified': '内容未变化',
      'preparing': '准备中',
      'pending': '待批准',
      'executing': '执行中',
      'executed': '已完成',
      'approved': '已批准，等待执行',
      'rejected': '已拒绝',
      'expired': '已过期',
    }[value?.toString()] ??
    (value?.toString() ?? '等待首次发现');
