import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/utils/storage.dart';

/// 批量取关：待移除名单 + 前台定时移除引擎
///
/// 规则类型（unfollowRuleType）：
/// 0 等长时间：每 unfollowIntervalSec 秒移除一个
/// 1 间歇：每 unfollowIntervalSec 秒移除一个，
///          每移除 unfollowBatchCount 个休息 unfollowRestSec 秒
/// 2 随机：每 unfollowBaseSec 秒 + [0, unfollowRandMaxSec) 伪随机秒数移除一个
///
/// 移除目标已不在关注列表时忽略并继续（不报错）。
/// 名单移除完成后弹窗询问是否保存到 Zeitlind/Unfollow/yyyy-mm-dd.txt
class UnfollowService extends GetxService {
  static UnfollowService get instance => Get.find<UnfollowService>();

  final Box setting = GStrorage.setting;

  /// 待移除名单：{mid, uname}（uname 便于展示与存档）
  RxList<Map<String, dynamic>> pendingList = <Map<String, dynamic>>[].obs;

  /// 是否正在运行移除循环
  RxBool running = false.obs;

  /// 最近一次移除结果（用于 UI 展示）
  RxInt removedCount = 0.obs;
  RxInt skippedCount = 0.obs;

  Timer? _timer;
  final Random _random = Random();

  @override
  void onInit() {
    super.onInit();
    // 启动时若名单非空（服务常驻内存，一般不会），可自动恢复
  }

  int get ruleType =>
      setting.get(SettingBoxKey.unfollowRuleType, defaultValue: 0);
  int get intervalSec =>
      setting.get(SettingBoxKey.unfollowIntervalSec, defaultValue: 60);
  int get batchCount =>
      setting.get(SettingBoxKey.unfollowBatchCount, defaultValue: 5);
  int get restSec =>
      setting.get(SettingBoxKey.unfollowRestSec, defaultValue: 300);
  int get baseSec =>
      setting.get(SettingBoxKey.unfollowBaseSec, defaultValue: 60);
  int get randMaxSec =>
      setting.get(SettingBoxKey.unfollowRandMaxSec, defaultValue: 20);

  /// 加入待移除名单（重复 mid 忽略）
  void addPending(List<Map<String, dynamic>> items) {
    final existing = pendingList.map((e) => e['mid']).toSet();
    for (final it in items) {
      if (!existing.contains(it['mid'])) {
        pendingList.add(it);
      }
    }
  }

  void removePending(int mid) {
    pendingList.removeWhere((e) => e['mid'] == mid);
  }

  void clearPending() {
    pendingList.clear();
    removedCount.value = 0;
    skippedCount.value = 0;
  }

  /// 开始前台移除循环
  void start() {
    if (running.value || pendingList.isEmpty) return;
    running.value = true;
    _archiveSnapshot = List<Map<String, dynamic>>.from(pendingList);
    SmartDialog.showToast(
        '开始批量取关：待移除 ${pendingList.length} 个（前台运行）');
    _scheduleNext(first: true);
  }

  /// 停止循环（保留剩余名单）
  void stop() {
    _timer?.cancel();
    _timer = null;
    running.value = false;
    SmartDialog.showToast(
        '已暂停：剩余 ${pendingList.length} 个待移除（名单保留）');
  }

  void _scheduleNext({bool first = false}) {
    if (!running.value) return;
    Duration delay;
    if (first) {
      delay = Duration.zero;
    } else {
      delay = _nextDelay();
    }
    _timer = Timer(delay, _removeOne);
    if (!first) {
      SmartDialog.showToast('下一次移除：${delay.inSeconds} 秒后');
    }
  }

  /// 计算下一次移除的间隔（按当前规则）
  Duration _nextDelay() {
    switch (ruleType) {
      case 1:
        // 间歇规则：每 batchCount 个休息 restSec
        if (removedCount.value > 0 &&
            (removedCount.value + skippedCount.value) % batchCount == 0) {
          return Duration(seconds: restSec);
        }
        return Duration(seconds: intervalSec);
      case 2:
        // 随机规则：baseSec + [0, randMaxSec)
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
    final int mid = item['mid'];
    final String uname = item['uname'] ?? '';
    try {
      // act=2 取关；已取关时服务端返回非 0 code，按忽略处理
      final res = await VideoHttp.relationMod(mid: mid, act: 2, reSrc: 11);
      if (res['status']) {
        removedCount.value++;
        SmartDialog.showToast('已移除：$uname（$mid）');
      } else {
        // 已经取消关注等情形：忽略并继续
        skippedCount.value++;
        SmartDialog.showToast('跳过：$uname（${res['msg']}）');
      }
    } catch (_) {
      skippedCount.value++;
    }
    pendingList.removeWhere((e) => e['mid'] == mid);

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
    SmartDialog.dismiss();
    _promptSaveList();
  }

  /// 完成后弹窗：询问保存本次名单到 Zeitlind/Unfollow/yyyy-mm-dd.txt
  void _promptSaveList() {
    SmartDialog.show(
      useSystem: true,
      tag: 'unfollowDone',
      builder: (BuildContext context) {
        return _UnfollowDoneDialog(
          removed: removedCount.value,
          skipped: skippedCount.value,
          onSave: (path) async {
            SmartDialog.dismiss(tag: 'unfollowDone');
            await _saveListTo(path);
          },
          onClose: () => SmartDialog.dismiss(tag: 'unfollowDone'),
        );
      },
    );
    // total 供后续统计（clearPending 由用户决定）
  }

  /// 保存名单文件（格式：mid 用户名，按行）
  Future<String?> _saveListTo(String customDir) async {
    try {
      final now = DateTime.now();
      final String date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final Directory dir = Directory(customDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final File file = File('${dir.path}/$date.txt');
      final StringBuffer sb = StringBuffer();
      sb.writeln('# 批量取关名单 $date');
      sb.writeln(
          '# 规则: $ruleDescription，成功 ${removedCount.value}，跳过 ${skippedCount.value}');
      for (final e in _archiveSnapshot) {
        sb.writeln('${e['mid']} ${e['uname']}');
      }
      await file.writeAsString(sb.toString());
      SmartDialog.showToast('已保存：${file.path}');
      return file.path;
    } catch (e) {
      SmartDialog.showToast('保存失败：$e');
      return null;
    }
  }

  /// 完成时的名单快照（_finish 后 pendingList 已清）
  List<Map<String, dynamic>> _archiveSnapshot = [];

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

class _UnfollowDoneDialog extends StatelessWidget {
  final int removed;
  final int skipped;
  final Future<void> Function(String path) onSave;
  final VoidCallback onClose;

  const _UnfollowDoneDialog({
    required this.removed,
    required this.skipped,
    required this.onSave,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('批量取关完成'),
      content: Text('成功移除 $removed 个，跳过 $skipped 个。\n'
          '是否保存本次名单到 Zeitlind/Unfollow/ 日期.txt？'),
      actions: [
        TextButton(onPressed: onClose, child: const Text('不保存')),
        TextButton(
          onPressed: () => onSave('/storage/emulated/0/Download/Zeitlind/Unfollow'),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
