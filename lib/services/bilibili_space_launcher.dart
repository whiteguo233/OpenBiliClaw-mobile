import 'package:url_launcher/url_launcher.dart';

/// Opens a Bilibili UP 主 space in the native app, falling back to the web.
///
/// This stays separate from [ContentLauncher] because the native player page
/// imports it, while [ContentLauncher] already imports that page; keeping the
/// space launch plan here avoids a circular import between the two.
class BilibiliSpaceLauncher {
  const BilibiliSpaceLauncher._();

  static final RegExp _midPattern = RegExp(r'^[1-9]\d*$');

  static bool isValidMid(String mid) => _midPattern.hasMatch(mid.trim());

  /// Native app links first; the canonical web URL is always the last
  /// candidate so users without the Bilibili app still reach the space.
  static List<Uri> buildUris({required String mid}) {
    final id = mid.trim();
    if (!isValidMid(id)) return const [];
    return [
      Uri(scheme: 'bilibili', host: 'space', path: '/$id'),
      Uri.https('space.bilibili.com', '/$id'),
    ];
  }

  /// Returns true when one candidate was handed off successfully.
  static Future<bool> open({required String mid}) async {
    for (final uri in buildUris(mid: mid)) {
      try {
        final mode = uri.scheme == 'https'
            ? LaunchMode.inAppBrowserView
            : LaunchMode.externalApplication;
        if (await launchUrl(uri, mode: mode)) return true;
      } catch (_) {
        // The native app is optional; continue to the web fallback.
      }
    }
    return false;
  }
}
