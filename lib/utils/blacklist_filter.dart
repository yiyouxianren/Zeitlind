import 'package:hive/hive.dart';
import 'package:pilipala/utils/storage.dart';

class BlacklistFilter {
  const BlacklistFilter._();

  static bool get enabled => GStrorage.setting.get(
        SettingBoxKey.enableBlacklistFilter,
        defaultValue: true,
      );

  static Set<int> get blackMids => _toMids(
        GStrorage.setting.get(
          SettingBoxKey.blackMidsList,
          defaultValue: const <int>[-1],
        ),
      );

  static bool isBlocked(dynamic mid,
      {bool? enabledOverride, Iterable<int>? blackMidsOverride}) {
    if (!(enabledOverride ?? enabled)) return false;
    final normalizedMid = toMid(mid);
    if (normalizedMid == null) return false;
    return (blackMidsOverride ?? blackMids).contains(normalizedMid);
  }

  static List<T> filter<T>(Iterable<T> items, dynamic Function(T item) midOf,
      {bool? enabledOverride, Iterable<int>? blackMidsOverride}) {
    return items
        .where((item) => !isBlocked(midOf(item),
            enabledOverride: enabledOverride,
            blackMidsOverride: blackMidsOverride))
        .toList();
  }

  static int? toMid(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Set<int> _toMids(dynamic value) {
    if (value is! Iterable) return <int>{-1};
    return value.map(toMid).whereType<int>().toSet();
  }
}

class BlacklistCache {
  const BlacklistCache._();

  static Future<void> add(int mid) async {
    final mids = BlacklistFilter.blackMids..add(mid);
    await GStrorage.setting.put(SettingBoxKey.blackMidsList, mids.toList());
  }

  static Future<void> remove(int mid) async {
    final mids = BlacklistFilter.blackMids..remove(mid);
    await GStrorage.setting.put(SettingBoxKey.blackMidsList, mids.toList());
  }

  static Future<void> addName(int mid, String name) async {
    if (name.trim().isEmpty) return;
    final raw = GStrorage.setting.get(SettingBoxKey.blacklistNames);
    final names = raw is Map
        ? Map<dynamic, dynamic>.from(raw)
        : <dynamic, dynamic>{};
    names[mid] = name.trim();
    await GStrorage.setting.put(SettingBoxKey.blacklistNames, names);
  }

  static Future<void> removeName(int mid) async {
    final raw = GStrorage.setting.get(SettingBoxKey.blacklistNames);
    if (raw is! Map) return;
    final names = Map<dynamic, dynamic>.from(raw)..remove(mid);
    await GStrorage.setting.put(SettingBoxKey.blacklistNames, names);
  }
}
