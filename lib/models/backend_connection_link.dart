/// A phone connection QR is also a normal Mobile Web URL.
/// Only an embedded Tailnet node asks the App to use its own Tailscale client.
class BackendConnectionLink {
  const BackendConnectionLink({
    required this.backendUri,
    required this.usesEmbeddedTailnet,
  });

  final Uri backendUri;
  final bool usesEmbeddedTailnet;

  factory BackendConnectionLink.parse(String input) {
    final value = input.trim();
    if (value.length > 4096) {
      throw const FormatException('连接链接过长');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('请扫描 OpenBiliClaw 的 HTTP / HTTPS 连接二维码');
    }
    final host = uri.host
        .toLowerCase()
        .replaceAll(RegExp(r'^\[|\]$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.startsWith('127.') ||
        host == '0.0.0.0' ||
        RegExp(r'^(?:[0-9]+|0x[0-9a-f]+)$').hasMatch(host) ||
        host == '::' ||
        host == '::1' ||
        host.startsWith('::ffff:') ||
        host.startsWith('169.254.') ||
        RegExp(r'^fe[89ab][\da-f]:').hasMatch(host)) {
      throw const FormatException('这是电脑本机地址，手机无法访问；请选择局域网或 Tailscale 二维码');
    }
    final modes = uri.queryParametersAll['obc_connection'] ?? const [];
    if (modes.length > 1 ||
        (modes.isNotEmpty &&
            !const ['direct', 'tailscale'].contains(modes.single))) {
      throw const FormatException('无法识别二维码中的连接方式');
    }
    final prefix = uri.path
        .replaceFirst(RegExp(r'/(m|web|api)(/index\.html)?/?$'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    return BackendConnectionLink(
      backendUri: Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: prefix,
      ),
      usesEmbeddedTailnet: modes.isNotEmpty && modes.single == 'tailscale',
    );
  }
}
