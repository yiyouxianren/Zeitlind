import 'dart:async';

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/utils/storage.dart';

/// 极简模式全局状态：开关 + 每日定时自动开启/关闭
///
/// 极简模式生效范围：
/// - 底部导航移除「动态」「排行榜」
/// - 首页仅显示收藏夹（含默认收藏夹与自建收藏夹，点进可查看内容）
/// - 搜索页关闭「大家都在搜」「搜索历史」与输入词联想推荐
class SimpleModeService extends GetxService {
  static SimpleModeService get instance => Get.find<SimpleModeService>();

  final Box setting = GStrorage.setting;

  /// 极简模式当前状态（响应式，各页面 Obx 监听）
  RxBool enabled = false.obs;

  /// 每日自动开启时刻（null = 不启用定时开启）
  RxnString autoOnTime = RxnString();

  /// 每日自动关闭时刻（null = 不启用定时关闭）
  RxnString autoOffTime = RxnString();

  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    enabled.value =
        setting.get(SettingBoxKey.enableSimpleMode, defaultValue: false);
    autoOnTime.value = _readTime(SettingBoxKey.simpleModeAutoOn);
    autoOffTime.value = _readTime(SettingBoxKey.simpleModeAutoOff);
    _startTimer();
  }

  String? _readTime(String key) {
    final v = setting.get(key);
    return v is String && RegExp(r'^\d{2}:\d{2}$').hasMatch(v) ? v : null;
  }

  /// 手动切换开关
  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await setting.put(SettingBoxKey.enableSimpleMode, value);
  }

  /// 设置定时开启时刻，传 null 清除
  Future<void> setAutoOnTime(String? time) async {
    autoOnTime.value = time;
    await setting.put(SettingBoxKey.simpleModeAutoOn, time ?? '');
  }

  /// 设置定时关闭时刻，传 null 清除
  Future<void> setAutoOffTime(String? time) async {
    autoOffTime.value = time;
    await setting.put(SettingBoxKey.simpleModeAutoOff, time ?? '');
  }

  /// 每分钟检查一次是否到达定时切换时刻
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkSchedule());
    _checkSchedule();
  }

  void _checkSchedule() {
    final now = DateTime.now();
    final hhmm =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (autoOnTime.value == hhmm && !enabled.value) {
      setEnabled(true);
    }
    if (autoOffTime.value == hhmm && enabled.value) {
      setEnabled(false);
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
