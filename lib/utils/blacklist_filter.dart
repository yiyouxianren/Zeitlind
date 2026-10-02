import 'dart:async';

import 'package:pilipala/http/black.dart';
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

/// 黑名单变动的事件总线：本地拉黑/移除后广播，
/// 让已渲染的列表（搜索置顶卡片等）无需重进页面即可同步过滤。
class BlacklistUpdateBus {
  BlacklistUpdateBus._();

  static final StreamController<Set<int>> _controller =
      StreamController<Set<int>>.broadcast();

  static Stream<Set<int>> get stream => _controller.stream;

  static void notify() {
    if (!_controller.isClosed) {
      _controller.add(BlacklistFilter.blackMids);
    }
  }
}

/// 从服务端全量同步黑名单（拉黑/移除操作后校准，
/// 覆盖其他设备或在网页端做的改动），结果写入本地缓存并广播。
class BlacklistSync {
  const BlacklistSync._();

  static bool _running = false;

  static Future<void> refresh() async {
    if (_running) return;
    _running = true;
    try {
      int pn = 1;
      final Map<int, String> serverEntries = {};
      while (true) {
        final res = await BlackHttp.blackList(pn: pn, ps: 50);
        if (res['status'] != true) break;
        final list = res['data'].list ?? const <dynamic>[];
        if (list.isEmpty) break;
        for (final item in list) {
          final mid = item.mid;
          if (mid != null) serverEntries[mid] = item.uname ?? '';
        }
        if (serverEntries.length >= (res['data'].total ?? 0)) break;
        pn++;
      }
      if (serverEntries.isNotEmpty) {
        // 以服务端为准覆写本地 mids 与名称缓存
        await GStrorage.setting
            .put(SettingBoxKey.blackMidsList, serverEntries.keys.toList());
        final Map<dynamic, dynamic> names = {};
        serverEntries.forEach((mid, name) {
          if (name.trim().isNotEmpty) names[mid] = name.trim();
        });
        await GStrorage.setting.put(SettingBoxKey.blacklistNames, names);
        BlacklistUpdateBus.notify();
      }
    } catch (_) {
      // 网络异常时保留本地缓存，下次操作后再同步
    } finally {
      _running = false;
    }
  }
}

class BlacklistCache {
  const BlacklistCache._();

  static Future<void> add(int mid) async {
    final mids = BlacklistFilter.blackMids..add(mid);
    await GStrorage.setting.put(SettingBoxKey.blackMidsList, mids.toList());
    BlacklistUpdateBus.notify();
  }

  static Future<void> remove(int mid) async {
    final mids = BlacklistFilter.blackMids..remove(mid);
    await GStrorage.setting.put(SettingBoxKey.blackMidsList, mids.toList());
    BlacklistUpdateBus.notify();
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
