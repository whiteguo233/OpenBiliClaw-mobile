import '../api/utils.dart';

class ProfileSummary {
  final String portrait;
  final List<ProfileLayer> layers;
  final List<String> deepNeeds;
  final ProfileMbti mbti;
  final List<String> values;
  final List<String> motivationalDrivers;
  final List<ProfileInterest> interests;
  final List<ProfileInterest> avoidances;
  final List<String> favoriteUpUsers;
  final String lifeStage;
  final String currentPhase;
  final List<String> cognitiveStyle;
  final ProfileStyle style;
  final ProfileContext context;
  final double explorationOpenness;
  final List<ProfileSpeculation> speculativeInterests;
  final List<ProfileSpeculation> speculativeAvoidances;
  final List<ProfileCognitionUpdate> cognitionUpdates;
  final bool hasMoreCognitionUpdates;
  final String nextCognitionCursor;
  final List<ProfileInsight> activeInsights;
  final List<ProfileAwareness> recentAwareness;
  final Map<String, dynamic> overrides;
  final bool initialized;

  const ProfileSummary({
    this.portrait = '',
    this.layers = const [],
    this.deepNeeds = const [],
    this.mbti = const ProfileMbti(),
    this.values = const [],
    this.motivationalDrivers = const [],
    this.interests = const [],
    this.avoidances = const [],
    this.favoriteUpUsers = const [],
    this.lifeStage = '',
    this.currentPhase = '',
    this.cognitiveStyle = const [],
    this.style = const ProfileStyle(),
    this.context = const ProfileContext(),
    this.explorationOpenness = 0.5,
    this.speculativeInterests = const [],
    this.speculativeAvoidances = const [],
    this.cognitionUpdates = const [],
    this.hasMoreCognitionUpdates = false,
    this.nextCognitionCursor = '',
    this.activeInsights = const [],
    this.recentAwareness = const [],
    this.overrides = const {},
    this.initialized = true,
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    final legacyLayers = _parseLayers(json['layers']);
    final legacyInterests = _parseInterests(json['interests']);
    final legacyAvoidances = _parseInterests(json['avoidances']);
    return ProfileSummary(
      portrait: _decode(json['portrait'] ?? json['personality_portrait']),
      layers: legacyLayers.isNotEmpty
          ? legacyLayers
          : _parseTraits(json['core_traits']),
      deepNeeds: _strings(json['deep_needs']),
      mbti: ProfileMbti.fromJson(_asMap(json['mbti']) ?? const {}),
      values: _strings(json['values']),
      motivationalDrivers: _strings(json['motivational_drivers']),
      interests: legacyInterests.isNotEmpty
          ? legacyInterests
          : _parseDomains(json['likes']),
      avoidances: legacyAvoidances.isNotEmpty
          ? legacyAvoidances
          : _parseDomains(json['dislikes']),
      favoriteUpUsers: _strings(json['favorite_up_users']),
      lifeStage: _decode(json['life_stage']),
      currentPhase: _decode(json['current_phase']),
      cognitiveStyle: _strings(json['cognitive_style']),
      style: ProfileStyle.fromJson(_asMap(json['style']) ?? const {}),
      context: ProfileContext.fromJson(_asMap(json['context']) ?? const {}),
      explorationOpenness: _toDouble(json['exploration_openness'], 0.5),
      speculativeInterests: _asList(json['speculative_interests'])
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map((item) => ProfileSpeculation.fromJson(item, avoidance: false))
          .toList(),
      speculativeAvoidances: _asList(json['speculative_avoidances'])
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map((item) => ProfileSpeculation.fromJson(item, avoidance: true))
          .toList(),
      cognitionUpdates: _asList(json['recent_cognition_updates'])
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(ProfileCognitionUpdate.fromJson)
          .toList(),
      hasMoreCognitionUpdates: json['has_more_cognition_updates'] == true,
      nextCognitionCursor: _decode(json['next_cognition_cursor']),
      activeInsights: _asList(json['active_insights'])
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(ProfileInsight.fromJson)
          .toList(),
      recentAwareness: _asList(json['recent_awareness'])
          .map(_asMap)
          .whereType<Map<String, dynamic>>()
          .map(ProfileAwareness.fromJson)
          .toList(),
      overrides: _asMap(json['overrides']) ?? const {},
      initialized: json['initialized'] != false,
    );
  }

  bool get hasContent =>
      portrait.isNotEmpty ||
      layers.isNotEmpty ||
      interests.isNotEmpty ||
      avoidances.isNotEmpty;
}

class ProfileLayer {
  final String name;
  final String summary;
  final double weight;

  const ProfileLayer({required this.name, this.summary = '', this.weight = 0});

  factory ProfileLayer.fromJson(Map<String, dynamic> json) => ProfileLayer(
    name: _decode(json['name'] ?? json['trait']),
    summary: _decode(json['summary']),
    weight: _toDouble(json['weight']),
  );
}

class ProfileInterest {
  final String name;
  final double weight;
  final String category;
  final String reason;
  final List<String> specifics;

  const ProfileInterest({
    this.name = '',
    this.weight = 0,
    this.category = '',
    this.reason = '',
    this.specifics = const [],
  });

  factory ProfileInterest.fromJson(Map<String, dynamic> json) {
    final specifics = _specificNames(json['specifics']);
    return ProfileInterest(
      name: _decode(json['name'] ?? json['domain']),
      weight: _toDouble(json['weight']),
      category: _decode(json['category'] ?? json['domain']),
      reason: _decode(json['reason']),
      specifics: specifics,
    );
  }
}

class ProfileMbti {
  final String type;
  final double confidence;
  final Map<String, ProfileMbtiDimension> dimensions;

  const ProfileMbti({
    this.type = '',
    this.confidence = 0,
    this.dimensions = const {},
  });

  factory ProfileMbti.fromJson(Map<String, dynamic> json) {
    final rawDimensions = _asMap(json['dimensions']) ?? const {};
    return ProfileMbti(
      type: _decode(json['type']),
      confidence: _toDouble(json['confidence']),
      dimensions: rawDimensions.map((key, value) {
        return MapEntry(
          key,
          ProfileMbtiDimension.fromJson(_asMap(value) ?? const {}),
        );
      }),
    );
  }
}

class ProfileMbtiDimension {
  final String pole;
  final double strength;

  const ProfileMbtiDimension({this.pole = '', this.strength = 0});

  factory ProfileMbtiDimension.fromJson(Map<String, dynamic> json) =>
      ProfileMbtiDimension(
        pole: _decode(json['pole']),
        strength: _toDouble(json['strength']),
      );
}

class ProfileStyle {
  final String preferredDuration;
  final String preferredPace;
  final double qualitySensitivity;
  final double humorPreference;
  final double depthPreference;

  const ProfileStyle({
    this.preferredDuration = '',
    this.preferredPace = '',
    this.qualitySensitivity = 0.5,
    this.humorPreference = 0.5,
    this.depthPreference = 0.5,
  });

  factory ProfileStyle.fromJson(Map<String, dynamic> json) => ProfileStyle(
    preferredDuration: _decode(json['preferred_duration']),
    preferredPace: _decode(json['preferred_pace']),
    qualitySensitivity: _toDouble(json['quality_sensitivity'], 0.5),
    humorPreference: _toDouble(json['humor_preference'], 0.5),
    depthPreference: _toDouble(json['depth_preference'], 0.5),
  );
}

class ProfileContext {
  final String weekdayPatterns;
  final String weekendPatterns;
  final String timeOfDayPatterns;
  final String sessionType;

  const ProfileContext({
    this.weekdayPatterns = '',
    this.weekendPatterns = '',
    this.timeOfDayPatterns = '',
    this.sessionType = '',
  });

  factory ProfileContext.fromJson(Map<String, dynamic> json) => ProfileContext(
    weekdayPatterns: _decode(json['weekday_patterns']),
    weekendPatterns: _decode(json['weekend_patterns']),
    timeOfDayPatterns: _decode(json['time_of_day_patterns']),
    sessionType: _decode(json['session_type']),
  );
}

class ProfileSpeculation {
  final String domain;
  final String reason;
  final double confidence;
  final String probeMode;
  final bool challenge;
  final int confirmationCount;
  final int confirmationThreshold;
  final List<String> specifics;
  final bool avoidance;

  const ProfileSpeculation({
    required this.domain,
    this.reason = '',
    this.confidence = 0,
    this.probeMode = '',
    this.challenge = false,
    this.confirmationCount = 0,
    this.confirmationThreshold = 3,
    this.specifics = const [],
    this.avoidance = false,
  });

  factory ProfileSpeculation.fromJson(
    Map<String, dynamic> json, {
    required bool avoidance,
  }) => ProfileSpeculation(
    domain: _decode(json['domain']),
    reason: _decode(json['reason']),
    confidence: _toDouble(json['confidence']),
    probeMode: _decode(json['probe_mode'] ?? json['source_mode']),
    challenge: json['challenge'] == true,
    confirmationCount: _integer(json['confirmation_count']),
    confirmationThreshold: _integer(json['confirmation_threshold'], 3),
    specifics: _specificNames(json['specifics']),
    avoidance: avoidance,
  );
}

class ProfileCognitionUpdate {
  final String summary;
  final String contextLine;
  final String impact;
  final String reasoning;
  final String evidence;
  final String sourceLabel;
  final String createdAt;

  const ProfileCognitionUpdate({
    this.summary = '',
    this.contextLine = '',
    this.impact = '',
    this.reasoning = '',
    this.evidence = '',
    this.sourceLabel = '',
    this.createdAt = '',
  });

  factory ProfileCognitionUpdate.fromJson(Map<String, dynamic> json) =>
      ProfileCognitionUpdate(
        summary: _decode(json['summary']),
        contextLine: _decode(json['context_line']),
        impact: _decode(json['impact']),
        reasoning: _decode(json['reasoning']),
        evidence: _decode(json['evidence']),
        sourceLabel: _decode(json['source_label'] ?? json['source']),
        createdAt: _decode(json['created_at']),
      );
}

class ProfileInsight {
  final String hypothesis;
  final List<String> evidence;
  final double confidence;
  final bool validated;
  final String createdAt;

  const ProfileInsight({
    this.hypothesis = '',
    this.evidence = const [],
    this.confidence = 0,
    this.validated = false,
    this.createdAt = '',
  });

  factory ProfileInsight.fromJson(Map<String, dynamic> json) => ProfileInsight(
    hypothesis: _decode(json['hypothesis']),
    evidence: _strings(json['evidence']),
    confidence: _toDouble(json['confidence']),
    validated: json['validated'] == true,
    createdAt: _decode(json['created_at']),
  );
}

class ProfileAwareness {
  final String date;
  final String observation;
  final String trend;
  final String emotionGuess;

  const ProfileAwareness({
    this.date = '',
    this.observation = '',
    this.trend = '',
    this.emotionGuess = '',
  });

  factory ProfileAwareness.fromJson(Map<String, dynamic> json) =>
      ProfileAwareness(
        date: _decode(json['date']),
        observation: _decode(json['observation']),
        trend: _decode(json['trend']),
        emotionGuess: _decode(json['emotion_guess']),
      );
}

String _decode(dynamic value) => decodeHtml(value?.toString() ?? '');

double _toDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _integer(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<dynamic> _asList(dynamic value) => value is List ? value : const [];

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<String> _strings(dynamic value) {
  return _asList(
    value,
  ).map(_decode).where((item) => item.trim().isNotEmpty).toList();
}

List<String> _specificNames(dynamic value) {
  return _asList(value)
      .map((item) {
        final map = _asMap(item);
        return map == null ? _decode(item) : _decode(map['name']);
      })
      .where((item) => item.isNotEmpty)
      .toList();
}

List<ProfileLayer> _parseLayers(dynamic value) {
  return _asList(value)
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map(ProfileLayer.fromJson)
      .where((layer) => layer.name.isNotEmpty)
      .toList();
}

List<ProfileLayer> _parseTraits(dynamic value) {
  return _asList(value)
      .map((item) {
        final map = _asMap(item);
        return map != null
            ? ProfileLayer.fromJson(map)
            : ProfileLayer(name: _decode(item));
      })
      .where((layer) => layer.name.isNotEmpty)
      .toList();
}

List<ProfileInterest> _parseInterests(dynamic value) {
  return _asList(value)
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map(ProfileInterest.fromJson)
      .where((interest) => interest.name.isNotEmpty)
      .toList();
}

List<ProfileInterest> _parseDomains(dynamic value) {
  return _asList(value)
      .map((item) {
        final map = _asMap(item);
        if (map == null) return ProfileInterest(name: _decode(item));
        final specifics = _specificNames(map['specifics']);
        final explicitReason = _decode(map['reason']);
        return ProfileInterest(
          name: _decode(map['domain'] ?? map['name']),
          weight: _toDouble(map['weight']),
          category: _decode(map['category'] ?? map['domain']),
          reason: explicitReason.isNotEmpty
              ? explicitReason
              : specifics.isNotEmpty
              ? '细分：${specifics.join('、')}'
              : '',
          specifics: specifics,
        );
      })
      .where((interest) => interest.name.isNotEmpty)
      .toList();
}
