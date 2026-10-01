import 'package:pilipala/models/dynamics/result.dart';
import 'package:pilipala/utils/keyword_filter.dart';
import 'package:pilipala/utils/storage.dart';

class DynamicFilter {
  const DynamicFilter._();

  static bool shouldBlock(
    DynamicItemModel item, {
    bool? scopeEnabledOverride,
    Iterable<String>? literalOverride,
    Iterable<String>? regexOverride,
    bool? blacklistNameOverride,
  }) {
    final enabled = scopeEnabledOverride ??
        GStrorage.setting.get(
          SettingBoxKey.enableKeywordFilterForFollowed,
          defaultValue: false,
        );
    if (!enabled) return false;
    return _shouldBlockModules(
          item.modules,
          enabled,
          literalOverride: literalOverride,
          regexOverride: regexOverride,
          blacklistNameOverride: blacklistNameOverride,
        ) ||
        (item.orig != null &&
            _shouldBlockModules(
              item.orig!.modules,
              enabled,
              literalOverride: literalOverride,
              regexOverride: regexOverride,
              blacklistNameOverride: blacklistNameOverride,
            ));
  }

  static bool _shouldBlockModules(
    ItemModulesModel? modules,
    bool enabled, {
    Iterable<String>? literalOverride,
    Iterable<String>? regexOverride,
    bool? blacklistNameOverride,
  }) {
    if (modules == null) return false;
    final dynamic = modules.moduleDynamic;
    final parts = <String>[];
    _add(parts, dynamic?.desc?.text);
    _add(parts, dynamic?.topic?.name);
    for (final node in dynamic?.desc?.richTextNodes ?? const []) {
      _add(parts, node.text);
      _add(parts, node.origText);
    }
    final major = dynamic?.major;
    _add(parts, major?.archive?.title);
    _add(parts, major?.archive?.desc);
    _add(parts, major?.ugcSeason?.title);
    _add(parts, major?.ugcSeason?.desc);
    _add(parts, major?.pgc?.title);
    _add(parts, major?.pgc?.desc);
    _add(parts, major?.opus?.title);
    _add(parts, major?.opus?.summary?.text);
    for (final node in major?.opus?.summary?.richTextNodes ?? const []) {
      _add(parts, node.text);
      _add(parts, node.origText);
    }
    _add(parts, major?.liveRcmd?.title);
    _add(parts, major?.live?.descFirst);
    _add(parts, major?.live?.descSecond);
    _add(parts, major?.none?.tips);
    _addMapValues(parts, major?.common);
    _addMapValues(parts, major?.courses);
    _addMapValues(parts, major?.music);
    return KeywordFilter.shouldBlock(
      description: parts,
      ownerName: modules.moduleAuthor?.name,
      literalOverride: literalOverride,
      regexOverride: regexOverride,
      blacklistNameOverride: blacklistNameOverride,
      enabledOverride: enabled,
    );
  }

  static void _addMapValues(List<String> values, Map? map) {
    if (map == null) return;
    for (final value in map.values) {
      if (value is Map) {
        _addMapValues(values, value);
      } else if (value is Iterable) {
        for (final item in value) {
          if (item is Map) {
            _addMapValues(values, item);
          } else {
            _add(values, item?.toString());
          }
        }
      } else {
        _add(values, value?.toString());
      }
    }
  }

  static void _add(List<String> values, String? value) {
    if (value != null && value.isNotEmpty) values.add(value);
  }
}
