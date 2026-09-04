import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/bilibili_auth.dart';
import 'package:openbiliclaw_app/models/bilibili_interaction.dart';
import 'package:openbiliclaw_app/models/bilibili_play.dart';

void main() {
  group('Bilibili auth protocol', () {
    test('parses logged-in status', () {
      final info = BilibiliAuthInfo.fromJson({
        'ok': true,
        'platform': 'bilibili',
        'status': 'logged_in',
        'user': {
          'mid': 123456,
          'name': '昵称',
          'face': 'https://i0.hdslb.com/face.png',
          'vip': true,
        },
        'scopes': ['video', 'danmaku', 'comment'],
        'expires_at': '2026-01-01T00:00:00Z',
      });

      expect(info.state, BilibiliAuthState.loggedIn);
      expect(info.isLoggedIn, isTrue);
      expect(info.user?.mid, 123456);
      expect(info.user?.name, '昵称');
      expect(info.scopes, contains('video'));
    });

    test('parses QR login confirmation', () {
      final poll = BilibiliQrPoll.fromJson({
        'ok': true,
        'status': 'confirmed',
        'user': {'mid': 1, 'name': '小明'},
        'message': '登录成功',
      });

      expect(poll.status, BilibiliQrStatus.confirmed);
      expect(poll.user?.name, '小明');
    });
  });

  group('Bilibili player protocol', () {
    test('parses play-url result with dash quality and headers', () {
      final result = BilibiliPlayResult.fromJson({
        'ok': true,
        'bvid': 'BV1xx411c7mD',
        'cid': 12345,
        'duration': 180,
        'pages': [
          {
            'cid': 12345,
            'page': 1,
            'part': 'P1',
            'duration': 180,
            'dimension': {'width': 1920, 'height': 1080},
          },
        ],
        'qualities': [
          {'qn': 80, 'label': '1080P', 'width': 1920, 'height': 1080},
        ],
        'video': {
          'qn': 80,
          'label': '1080P',
          'codec': 'avc',
          'url': 'https://upos.example.com/video.mp4',
          'backup_urls': ['https://upos.example.com/backup.mp4'],
          'width': 1920,
          'height': 1080,
          'mime_type': 'video/mp4',
        },
        'audio': {
          'qn': 30280,
          'codec': 'fmp4',
          'url': 'https://upos.example.com/audio.mp4',
          'bandwidth': 132000,
          'mime_type': 'audio/mp4',
        },
        'subtitles': [
          {
            'lan': 'zh-CN',
            'name': '中文',
            'url': 'https://sub.example.com/s.json',
          },
        ],
        'danmaku': {
          'url': 'https://api.bilibili.com/x/v1/dm/list.so?oid=12345',
          'headers': {
            'referer': 'https://www.bilibili.com',
            'user-agent': 'Mozilla/5.0',
          },
        },
        'headers': {
          'referer': 'https://www.bilibili.com',
          'user-agent': 'Mozilla/5.0',
          'cookie': 'SESSDATA=secret',
        },
        'expires_at': '2026-01-01T00:10:00Z',
      });

      expect(result.bvid, 'BV1xx411c7mD');
      expect(result.pages, hasLength(1));
      expect(result.pages.first.width, 1920);
      expect(result.qualities.single.qn, 80);
      expect(result.video?.url, startsWith('https://'));
      expect(result.audio?.codec, 'fmp4');
      expect(result.subtitles.single.lan, 'zh-CN');
      expect(result.danmaku.headers['referer'], 'https://www.bilibili.com');
      expect(result.headers['cookie'], 'SESSDATA=secret');
    });
  });

  group('Bilibili interaction protocol', () {
    test('parses video state and related content', () {
      final state = BilibiliVideoState.fromJson({
        'like': true,
        'coin': 2,
        'favorite': false,
        'watch_later': true,
      });
      final related = BilibiliRelatedVideo.fromJson({
        'bvid': 'BV1aa',
        'title': '相关视频',
        'pic': 'https://i0.hdslb.com/cover.jpg',
        'owner': {'name': 'UP'},
        'stat': {'view': 12345},
      });
      final comment = BilibiliComment.fromJson({
        'rpid': 100,
        'mid': 1,
        'uname': '用户',
        'message': '好看',
        'like_count': 10,
        'reply_count': 2,
        'replies': [
          {
            'rpid': 101,
            'mid': 2,
            'uname': '层主',
            'message': '同意',
            'like_count': 3,
          },
        ],
      });

      expect(state.like, isTrue);
      expect(state.coin, 2);
      expect(state.watchLater, isTrue);
      expect(related.bvid, 'BV1aa');
      expect(related.upName, 'UP');
      expect(comment.rpid, 100);
      expect(comment.likeCount, 10);
      expect(comment.replyCount, 2);
      expect(comment.replies.single.uname, '层主');
    });

    test('parses comment page with pagination fields', () {
      final page = BilibiliCommentPage.fromJson({
        'ok': true,
        'items': [
          {'rpid': 1, 'mid': 1, 'uname': '甲', 'message': '前排'},
          {'rpid': 2, 'mid': 2, 'uname': '乙', 'message': '后排'},
        ],
        'total': 45,
        'page': 2,
        'has_more': true,
      });

      expect(page.items, hasLength(2));
      expect(page.total, 45);
      expect(page.page, 2);
      expect(page.hasMore, isTrue);
    });

    test('comment page tolerates legacy backend without pagination fields', () {
      final page = BilibiliCommentPage.fromJson({
        'ok': true,
        'items': [
          {'mid': 1, 'uname': '甲', 'message': '前排', 'like_count': 5},
        ],
      });

      expect(page.items.single.likeCount, 5);
      expect(page.items.single.replies, isEmpty);
      expect(page.total, 0);
      expect(page.hasMore, isFalse);
    });
  });
}
