import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/utils/storage.dart';

/// 批量移除收藏：待移除名单 + 前台定时移除引擎
///
/// 名单项：{aid, bvid, title, mediaId}（title 用于存档展示）
/// 规则类型（unfavRuleType）：
/// 0 等长时间：每 unfavIntervalSec 秒移除一个
/// 1 间歇：每 unfavIntervalSec 秒移除一个，
///          每移除 unfavBatchCount 个休息 unfavRestSec 秒
/// 2 随机：每 unfavBaseSec 秒 + [0, unfavRandMaxSec) 伪随机秒数移除一个
///
/// 视频已被移除时忽略并继续（不报错）。
/// 完成后弹窗并默认保存名单到 Download/Zeitlind/danmaku/yyyy-mm-dd.txt
class UnfavService extends GetxService {
  static UnfavService get instance => Get.find<UnfavService>();

  final Box setting = GStrorage.setting;

  /// 待移除名单
  RxList<Map<String, dynamic>> pendingList = <Map<String, dynamic>>[].obs;

  /// 是否正在运行
  RxBool running = false.obs;

  RxInt removedCount = 0.obs;
  RxInt skippedCount = 0.obs;

  Timer? _timer;
  final Random _random = Random();

  List<Map<String, dynamic>> _archiveSnapshot = [];

  int get ruleType =>
      setting.get(SettingBoxKey.unfavRuleType, defaultValue: 0);
  int get intervalSec =>
      setting.get(SettingBoxKey.unfavIntervalSec, defaultValue: 60);
  int get batchCount =>
      setting.get(SettingBoxKey.unfavBatchCount, defaultValue: 5);
  int get restSec =>
      setting.get(SettingBoxKey.unfavRestSec, defaultValue: 300);
  int get baseSec =>
      setting.get(SettingBoxKey.unfavBaseSec, defaultValue: 60);
  int get randMaxSec =>
      setting.get(SettingBoxKey.unfavRandMaxSec, defaultValue: 20);

  /// 加入名单（按 aid 去重）
  void addPending(List<Map<String, dynamic>> items) {
    final existing = pendingList.map((e) => e['aid']).toSet();
    for (final it in items) {
      if (!existing.contains(it['aid'])) {
        pendingList.add(it);
      }
    }
  }

  void clearPending() {
    pendingList.clear();
    removedCount.value = 0;
    skippedCount.value = 0;
  }

  void start() {
    if (running.value || pendingList.isEmpty) return;
    running.value = true;
    _archiveSnapshot = List<Map<String, dynamic>>.from(pendingList);
    SmartDialog.showToast(
        '开始批量移除收藏：待移除 ${pendingList.length} 个（前台运行）');
    _scheduleNext(first: true);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    running.value = false;
    SmartDialog.showToast(
        '已暂停：剩余 ${pendingList.length} 个待移除（名单保留）');
  }

  void _scheduleNext({bool first = false}) {
    if (!running.value) return;
    final delay = first ? Duration.zero : _nextDelay();
    _timer = Timer(delay, _removeOne);
    if (!first) {
      SmartDialog.showToast('下一次移除：${delay.inSeconds} 秒后');
    }
  }

  Duration _nextDelay() {
    switch (ruleType) {
      case 1:
        if (removedCount.value > 0 &&
            (removedCount.value + skippedCount.value) % batchCount == 0) {
          return Duration(seconds: restSec);
        }
        return Duration(seconds: intervalSec);
      case 2:
        return Duration(
            seconds: baseSec + _random.nextInt(randMaxSec < 1 ? 1 : randMaxSec));
      case 0:
      default:
        return Duration(seconds: intervalSec);
    }
  }

  Future<void> _removeOne() async {
    if (!running.value) return;
    if (pendingList.isEmpty) {
      _finish();
      return;
    }
    final item = pendingList.first;
    final int aid = item['aid'];
    final String title = item['title'] ?? '';
    final int mediaId = item['mediaId'];
    try {
      // delIds = 收藏夹 id；视频已被移除时服务端返回非 0，按忽略处理
      final res = await VideoHttp.favVideo(
          aid: aid, addIds: '', delIds: mediaId.toString());
      if (res['status']) {
        removedCount.value++;
        SmartDialog.showToast('已移除收藏：$title');
      } else {
        skippedCount.value++;
        SmartDialog.showToast('跳过：$title（${res['msg']}）');
      }
    } catch (_) {
      skippedCount.value++;
    }
    pendingList.removeWhere((e) => e['aid'] == aid);

    if (pendingList.isEmpty) {
      _finish();
    } else {
      _scheduleNext();
    }
  }

  Future<void> _finish() async {
    running.value = false;
    _timer?.cancel();
    _timer = null;
    await _saveList();
    _showDoneDialog();
  }

  /// 每次移除完成（名单清空）后弹窗提示并保存名单
  Future<String?> _saveList() async {
    try {
      final now = DateTime.now();
      final String date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      const String root = '/storage/emulated/0/Download/Zeitlind/danmaku';
      final Directory dir = Directory(root);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final File file = File('$root/$date.txt');
      final StringBuffer sb = StringBuffer();
      sb.writeln('# 批量移除收藏名单 $date');
      sb.writeln(
          '# 规则: $ruleDescription，成功 ${removedCount.value}，跳过 ${skippedCount.value}');
      for (final e in _archiveSnapshot) {
        sb.writeln('${e['bvid']} ${e['aid']} ${e['title']}');
      }
      await file.writeAsString(sb.toString());
      return file.path;
    } catch (e) {
      SmartDialog.showToast('名单保存失败：$e');
      return null;
    }
  }

  void _showDoneDialog() {
    SmartDialog.show(
      useSystem: true,
      tag: 'unfavDone',
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('批量移除收藏完成'),
          content: Text('成功移除 ${removedCount.value} 个，'
              '跳过 ${skippedCount.value} 个。\n'
              '名单已保存到\nDownload/Zeitlind/danmaku/日期.txt'),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  String get ruleDescription {
    switch (ruleType) {
      case 1:
        return '间歇：${intervalSec}s/个，每 $batchCount 个休息 $restSec s';
      case 2:
        return '随机：${baseSec}s + [0,${randMaxSec}s)';
      case 0:
      default:
        return '等长：${intervalSec}s/个';
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
