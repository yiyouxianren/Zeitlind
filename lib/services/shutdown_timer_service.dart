// 定时关闭服务
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../plugin/pl_player/controller.dart';

class ShutdownTimerService {
  static final ShutdownTimerService _instance =
      ShutdownTimerService._internal();
  Timer? _shutdownTimer;
  Timer? _autoCloseDialogTimer;
  //定时退出
  int scheduledExitInMinutes = -1;
  bool exitApp = false;
  bool waitForPlayingCompleted = false;
  bool isWaiting = false;

  factory ShutdownTimerService() => _instance;

  ShutdownTimerService._internal();

  /// 是否有生效的定时
  bool get isActive => _shutdownTimer != null || isWaiting;

  /// 剩余时间（供 UI 倒计时显示）；未启用时为 null
  final ValueNotifier<Duration?> remaining = ValueNotifier<Duration?>(null);
  Timer? _tickTimer;

  void startShutdownTimer() {
    cancelShutdownTimer(); // Cancel any previous timer
    if (scheduledExitInMinutes == -1) {
      //使用toast提示用户已取消
      SmartDialog.showToast("取消定时关闭");
      return;
    }
    SmartDialog.showToast("设置 $scheduledExitInMinutes 分钟后定时关闭");
    final Duration duration = Duration(minutes: scheduledExitInMinutes);
    _shutdownTimer = Timer(duration, () => _shutdownDecider());
    // 倒计时显示：每秒刷新剩余时间
    final DateTime deadline = DateTime.now().add(duration);
    remaining.value = duration;
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = deadline.difference(DateTime.now());
      remaining.value = left.isNegative ? Duration.zero : left;
      if (left.isNegative) t.cancel();
    });
  }

  /// 设置自定义倒计时（时 + 分，最少 1 分钟）
  void startCustomTimer(int hours, int minutes) {
    final int totalMinutes = hours * 60 + minutes;
    if (totalMinutes < 1) {
      SmartDialog.showToast("至少需要 1 分钟");
      return;
    }
    scheduledExitInMinutes = totalMinutes;
    startShutdownTimer();
  }

  /// 剩余时间的可读文本（用于入口角标）
  String get remainingLabel {
    final d = remaining.value;
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _showTimeUpButPauseDialog() {
    SmartDialog.show(
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('定时关闭'),
          content: const Text('时间到啦！'),
          actions: <Widget>[
            TextButton(
              child: const Text('确认'),
              onPressed: () {
                cancelShutdownTimer();
                SmartDialog.dismiss();
              },
            ),
          ],
        );
      },
    );
  }

  void _showShutdownDialog() {
    SmartDialog.show(
      builder: (BuildContext dialogContext) {
        // Start the 10-second timer to auto close the dialog
        _autoCloseDialogTimer?.cancel();
        _autoCloseDialogTimer = Timer(const Duration(seconds: 10), () {
          SmartDialog.dismiss(); // Close the dialog
          _executeShutdown();
        });
        return AlertDialog(
          title: const Text('定时关闭'),
          content: const Text('将在10秒后执行，是否需要取消？'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消关闭'),
              onPressed: () {
                _autoCloseDialogTimer?.cancel(); // Cancel the auto-close timer
                cancelShutdownTimer(); // Cancel the shutdown timer
                SmartDialog.dismiss(); // Close the dialog
              },
            ),
          ],
        );
      },
    ).then((_) {
      // Cleanup when the dialog is dismissed
      _autoCloseDialogTimer?.cancel();
    });
  }

  void _shutdownDecider() {
    if (exitApp && !waitForPlayingCompleted) {
      _showShutdownDialog();
      return;
    }
    PlPlayerController plPlayerController =
        PlPlayerController(videoType: 'none');
    if (!exitApp && !waitForPlayingCompleted) {
      if (!plPlayerController.playerStatus.playing) {
        //仅提示用户
        _showTimeUpButPauseDialog();
      } else {
        _showShutdownDialog();
      }
      return;
    }
    //waitForPlayingCompleted
    if (!plPlayerController.playerStatus.playing) {
      _showShutdownDialog();
      return;
    }
    SmartDialog.showToast("定时关闭时间已到，等待当前视频播放完成");
    //监听播放完成
    //该方法依赖耦合实现，不够优雅
    isWaiting = true;
  }

  void handleWaitingFinished() {
    if (isWaiting) {
      _showShutdownDialog();
      isWaiting = false;
    }
  }

  void _executeShutdown() {
    if (exitApp) {
      //退出app
      exit(0);
    } else {
      //暂停播放
      PlPlayerController plPlayerController =
          PlPlayerController(videoType: 'none');
      if (plPlayerController.playerStatus.playing) {
        plPlayerController.pause();
        waitForPlayingCompleted = true;
        SmartDialog.showToast("已暂停播放");
      } else {
        SmartDialog.showToast("当前未播放");
      }
    }
  }

  void cancelShutdownTimer() {
    isWaiting = false;
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    _tickTimer?.cancel();
    remaining.value = null;
  }
}

final shutdownTimerService = ShutdownTimerService();
