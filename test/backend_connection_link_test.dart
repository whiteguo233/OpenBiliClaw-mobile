import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/backend_connection_link.dart';

void main() {
  for (final entry in {
    'http://192.168.1.7:8420/m/': 'http://192.168.1.7:8420',
    'http://100.100.1.2:19090/m/': 'http://100.100.1.2:19090',
    'https://obc.example.com/m/': 'https://obc.example.com',
    'https://obc.example.com:9443/prefix/m/':
        'https://obc.example.com:9443/prefix',
    'http://[fd12:3456:789a::7]:8420/m/': 'http://[fd12:3456:789a::7]:8420',
    'http://obc.example.com/prefix/api/': 'http://obc.example.com/prefix',
    'https://obc.example.com/prefix/web/index.html':
        'https://obc.example.com/prefix',
  }.entries) {
    test('imports ${entry.key} without the mobile UI path', () {
      final link = BackendConnectionLink.parse(entry.key);
      expect(link.backendUri.toString(), entry.value);
      expect(link.usesEmbeddedTailnet, false);
    });
  }

  test('embedded Tailnet mode travels in a browser-compatible URL', () {
    final link = BackendConnectionLink.parse(
      'http://100.100.1.3:8421/m/?obc_connection=tailscale',
    );
    expect(link.backendUri.toString(), 'http://100.100.1.3:8421');
    expect(link.usesEmbeddedTailnet, true);
  });

  test('query and fragment credentials never enter the saved address', () {
    final link = BackendConnectionLink.parse(
      'https://obc.example.com/prefix/m/?token=secret#password',
    );
    expect(link.backendUri.toString(), 'https://obc.example.com/prefix');
  });

  for (final input in [
    '',
    'not a connection link',
    'javascript:alert(1)',
    'file:///etc/passwd',
    'http://127.0.0.1:8420/m/',
    'http://localhost:8420/m/',
    'http://localhost.:8420/m/',
    'http://[::1]:8420/m/',
    'http://0.0.0.0:8420/m/',
    'http://[::]:8420/m/',
    'http://2130706433:8420/m/',
    'http://0x7f000001:8420/m/',
    'http://user:pass@obc.example.com/m/',
    'http://obc.example.com:99999/m/',
    'http://obc.example.com/m/?obc_connection=unknown',
    'http://obc.example.com/m/?obc_connection=direct&obc_connection=tailscale',
  ]) {
    test('rejects unusable scan payload $input', () {
      expect(() => BackendConnectionLink.parse(input), throwsFormatException);
    });
  }
}
