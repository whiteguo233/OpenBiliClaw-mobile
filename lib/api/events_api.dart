import 'dart:math';

import '../models/saved_item.dart';
import 'client.dart';

/// Best-effort behavior-event reporting used for content feedback that has
/// no recommendation id (e.g. saved-list cards), mirroring the web clients'
/// `sendBehaviorEvents` → `POST /api/events`.
class EventsApi {
  final ApiClient _client;
  EventsApi(this._client);

  String _newEventId() =>
      'mobile-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  /// Report feedback (like / dislike / comment) about a saved item.
  Future<Map<String, dynamic>> sendSavedFeedback(
    SavedItem item, {
    required String feedbackType,
    String note = '',
  }) async {
    final contentId = item.contentId.isNotEmpty ? item.contentId : item.bvid;
    return _client.post(
      '/events',
      body: {
        'events': [
          {
            'type': 'feedback',
            'source_platform': item.sourcePlatform,
            'title': item.title,
            'url': item.contentUrl,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'metadata': {
              'feedback_type': feedbackType,
              'bvid': contentId,
              'content_id': contentId,
              'feedback_note': note,
              'saved_feedback': true,
            },
            'event_id': _newEventId(),
          },
        ],
      },
      timeout: 35,
    );
  }
}
