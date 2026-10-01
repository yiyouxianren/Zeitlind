import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 重启 APP：杀掉当前进程并由系统重新拉起。
/// 用途：极简模式等"重启生效"的设置切换后立即应用。
/// 说明：不依赖第三方插件——直接 Process.kill 自身（Android 上
/// ActivityManager 的重启机制会因 ROM 差异不可靠），配合
/// alarm(0) 式退出后由 launcher 手动/自动重进即可完整重走初始化。
class AppRestart {
  AppRestart._();

  /// 延时 [delay] 后重启 APP。
  /// 先弹 toast 告知用户，随后杀进程（系统会回到桌面，用户重新打开
  /// 或由前台服务拉起），进程重启即完整重走 main() 初始化。
  static Future<void> restartAfter(BuildContext context,
      {Duration delay = const Duration(milliseconds: 500)}) async {
    SmartDialog.showToast('即将重启应用');
    await Future<void>.delayed(delay);
    if (Platform.isAndroid) {
      // 结束自身进程；exit(0) 在 Flutter Android 上等同杀进程，
      // 应用回到桌面，重新点开图标即冷启动
      exit(0);
    }
  }
}
