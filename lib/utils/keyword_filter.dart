import 'package:pilipala/utils/storage.dart';

class KeywordFilter {
  const KeywordFilter._();

  static bool shouldBlock({
    dynamic title,
    dynamic description,
    dynamic tags,
    dynamic ownerName,
    bool? enabledOverride,
    Iterable<String>? literalOverride,
    Iterable<String>? regexOverride,
    bool? blacklistNameOverride,
    Iterable<String>? blacklistNamesOverride,
  }) {
    final enabled = enabledOverride ??
        GStrorage.setting.get(
          SettingBoxKey.enableKeywordFilter,
          defaultValue: false,
        );
    if (!enabled) return false;

    final texts = <String>[
      ..._values(title),
      ..._values(description),
      ..._values(tags),
    ];
    if (texts.isEmpty && ownerName == null) return false;
    final content = texts.join('\n');
    final contentWithOwner = [
      ...texts,
      ..._values(ownerName),
    ].join('\n');

    final literals =
        literalOverride ?? _strings(SettingBoxKey.literalBlockKeywords);
    if (literals.any((word) => word.isNotEmpty && content.contains(word))) {
      return true;
    }

    final useNames = blacklistNameOverride ??
        GStrorage.setting.get(
          SettingBoxKey.enableBlacklistNameKeyword,
          defaultValue: true,
        );
    if (useNames) {
      final names = blacklistNamesOverride ?? _blacklistNames;
      if (names
          .any((name) => name.isNotEmpty && contentWithOwner.contains(name))) {
        return true;
      }
    }

    final regexes = regexOverride ?? _strings(SettingBoxKey.regexBlockKeywords);
    for (final expression in regexes.where((item) => item.isNotEmpty)) {
      try {
        if (RegExp(expression).hasMatch(contentWithOwner)) return true;
      } on FormatException {
        continue;
      }
    }
    return false;
  }

  static List<String> get _blacklistNames {
    final value = GStrorage.setting.get(SettingBoxKey.blacklistNames);
    if (value is! Map) return <String>[];
    return value.values
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<String> _strings(String key) {
    final value = GStrorage.setting.get(key, defaultValue: const <String>[]);
    if (value is! Iterable) return <String>[];
    return value.map((item) => item.toString()).toSet().toList();
  }

  static List<String> _values(dynamic value) {
    if (value == null) return <String>[];
    if (value is Iterable) return value.map((item) => item.toString()).toList();
    return [value.toString()];
  }
}

class KeywordSettings {
  const KeywordSettings._();

  static List<String> get literal => _read(SettingBoxKey.literalBlockKeywords);
  static List<String> get regex => _read(SettingBoxKey.regexBlockKeywords);

  static Future<void> put(String key, Iterable<String> values) async {
    final result = values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    await GStrorage.setting.put(key, result);
  }

  static List<String> _read(String key) {
    final value = GStrorage.setting.get(key, defaultValue: const <String>[]);
    return value is Iterable
        ? value.map((item) => item.toString()).toList()
        : <String>[];
  }
}
