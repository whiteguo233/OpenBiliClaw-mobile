/// Decode common HTML entities in API responses.
String decodeHtml(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&mdash;', '\u2014')
      .replaceAll('&ndash;', '\u2013')
      .replaceAll('&hellip;', '\u2026');
}

/// Build a proxy URL for cover images through the backend.
/// Direct URLs are often blocked by CORS.
/// When the backend password gate is on, image-proxy requires auth; pass the
/// session token as the query token the backend accepts on this path only.
String proxyImageUrl(String url, String baseUrl, {String? token}) {
  if (url.isEmpty) return '';
  final apiBase = baseUrl.replaceAll('/api', '');
  var result = '$apiBase/api/image-proxy?url=${Uri.encodeComponent(url)}';
  if (token != null && token.isNotEmpty) {
    result += '&token=${Uri.encodeComponent(token)}';
  }
  return result;
}
