import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// 下载进度通知（原生 NotificationCompat 封装）
/// Android 13+ 首次使用需授予通知权限（失败静默降级：仅无通知，不影响下载）
class DownloadNotification {
  DownloadNotification._();

  static const MethodChannel _channel =
      MethodChannel('com.Zeitlind.bill/download_notification');

  static bool _permissionRequested = false;

  /// Android 13+ 请求通知权限（只在首次调用时请求）
  static Future<void> ensurePermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // 权限服务异常时静默忽略（通知是增强体验，非必需）
    }
  }

  /// 显示/更新进度条通知
  /// [progress] 0-100；null 表示不确定进度（indeterminate）
  static Future<void> showProgress({
    required String title,
    required String text,
    int? progress,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showProgress', {
        'title': title,
        'text': text,
        'progress': progress ?? 0,
        'indeterminate': progress == null,
      });
    } catch (_) {
      // 原生层异常时静默忽略
    }
  }

  /// 完成通知（无进度条，可点击清除）
  static Future<void> done({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('done', {'title': title, 'text': text});
    } catch (_) {}
  }

  /// 移除通知
  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancel');
    } catch (_) {}
  }

  /// 启动下载保活前台服务（前台通知 + WakeLock）：
  /// 后台/锁屏期间防止进程被冻结导致下载停止
  static Future<void> startKeepAlive() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startKeepAlive');
    } catch (_) {}
  }

  /// 停止保活服务（下载全部结束/取消时）
  static Future<void> stopKeepAlive() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopKeepAlive');
    } catch (_) {}
  }

  /// 是否已忽略电池优化（锁屏保活的前提）
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod('isIgnoringBatteryOptimizations') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 跳转电池优化设置页（引导用户把应用加入白名单）
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  /// 查询厂商后台省电策略（华为 EMUI「省电策略」）。
  /// 返回：'unrestricted' | 'restricted' | 'unknown'（非华为或查询失败）
  static Future<String> getPowerSavePolicy() async {
    if (!Platform.isAndroid) return 'unrestricted';
    try {
      return await _channel.invokeMethod('getPowerSavePolicy') ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// 跳转华为「应用启动管理」页面（手动关闭「自动管理」后可设为无限制）
  static Future<void> openHuaweiAppLaunchSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openHuaweiAppLaunchSettings');
    } catch (_) {}
  }
}
