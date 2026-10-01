class LiveEmotePackage {
  final List<LiveEmote> emoticons;
  final int packageType;
  final String? cover;

  const LiveEmotePackage({
    required this.emoticons,
    required this.packageType,
    this.cover,
  });

  factory LiveEmotePackage.fromJson(Map<String, dynamic> json) {
    final rawEmoticons = json['emoticons'];
    return LiveEmotePackage(
      emoticons: rawEmoticons is List
          ? rawEmoticons
              .whereType<Map>()
              .map((e) => LiveEmote.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      packageType: (json['pkg_type'] as num?)?.toInt() ?? 0,
      cover: json['current_cover']?.toString(),
    );
  }
}

class LiveEmote {
  final String? emoji;
  final String? url;
  final int width;
  final int height;
  final String? unique;

  const LiveEmote({
    this.emoji,
    this.url,
    this.width = 80,
    this.height = 80,
    this.unique,
  });

  factory LiveEmote.fromJson(Map<String, dynamic> json) {
    return LiveEmote(
      emoji: json['emoji']?.toString(),
      url: json['url']?.toString(),
      width: (json['width'] as num?)?.toInt() ?? 80,
      height: (json['height'] as num?)?.toInt() ?? 80,
      unique: json['emoticon_unique']?.toString(),
    );
  }
}
