import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/views/native_bilibili_video_page.dart';

void main() {
  group('inflateDanmakuBytes', () {
    const xml = '<?xml version="1.0"?><i><d p="1.5,1,25,16777215">你好</d></i>';

    test('returns plain XML bytes unchanged', () {
      final plain = utf8.encode(xml);
      expect(inflateDanmakuBytes(plain), plain);
    });

    test('inflates raw deflate bodies (bilibili dm/list.so behavior)', () {
      final compressed = ZLibEncoder(raw: true).convert(utf8.encode(xml));
      expect(utf8.decode(inflateDanmakuBytes(compressed)), xml);
    });

    test('inflates zlib-wrapped bodies as a fallback', () {
      final compressed = ZLibEncoder().convert(utf8.encode(xml));
      expect(utf8.decode(inflateDanmakuBytes(compressed)), xml);
    });

    test('returns undecodable bytes unchanged instead of throwing', () {
      final garbage = [0x00, 0xFF, 0x12, 0x34];
      expect(inflateDanmakuBytes(garbage), garbage);
    });
  });
}
