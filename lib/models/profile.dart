import '../api/utils.dart';

class ProfileSummary {
  final String portrait;
  final List<ProfileLayer> layers;
  final List<ProfileInterest> interests;
  final List<ProfileInterest> avoidances;

  ProfileSummary({
    this.portrait = '',
    this.layers = const [],
    this.interests = const [],
    this.avoidances = const [],
  });

  factory ProfileSummary.fromJson(Map<String, dynamic> json) {
    return ProfileSummary(
      portrait: decodeHtml(json['portrait'] ?? ''),
      layers: (json['layers'] as List?)?.map((e) => ProfileLayer.fromJson(e)).toList() ?? [],
      interests: (json['interests'] as List?)?.map((e) => ProfileInterest.fromJson(e)).toList() ?? [],
      avoidances: (json['avoidances'] as List?)?.map((e) => ProfileInterest.fromJson(e)).toList() ?? [],
    );
  }
}

class ProfileLayer {
  final String name;
  final String summary;
  final double weight;

  ProfileLayer({required this.name, this.summary = '', this.weight = 0.0});

  factory ProfileLayer.fromJson(Map<String, dynamic> json) => ProfileLayer(
    name: decodeHtml(json['name'] ?? ''),
    summary: decodeHtml(json['summary'] ?? ''),
    weight: (json['weight'] ?? 0).toDouble(),
  );
}

class ProfileInterest {
  final String name;
  final double weight;
  final String category;
  final String reason;

  ProfileInterest({this.name = '', this.weight = 0.0, this.category = '', this.reason = ''});

  factory ProfileInterest.fromJson(Map<String, dynamic> json) => ProfileInterest(
    name: json['name'] ?? '',
    weight: (json['weight'] ?? 0).toDouble(),
    category: json['category'] ?? '',
    reason: json['reason'] ?? '',
  );
}
