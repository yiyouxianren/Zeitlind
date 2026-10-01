import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 启动时的权限预申请：
/// - 通知（Android 13+）：批量下载的进度/完成通知依赖
/// - 媒体读取（Android 13+，READ_MEDIA_* 系）：读取公共目录媒体文件
///   （离线列表扫描/导入旧缓存）
/// - 存储（WRITE/READ_EXTERNAL_STORAGE，Android 10-12）：
///   华为等厂商 ROM 的 FUSE 实现要求显式授予旧存储权限，否则对公共
///   Download 的读写会被拒（标准 AOSP 上 Android 10+ 无需申请，但申请
///   本身无害——系统会静默授予，不会重复弹窗）
/// 权限申请有 UI 依赖，必须在 runApp 之后的首帧触发（经 postFrameCallback），
/// 否则在引擎 attach 前 request() 会静默失败。
class StartupPermissions {
  StartupPermissions._();

  static bool _requested = false;

  static Future<void> ensureAll() async {
    if (_requested || !Platform.isAndroid) return;
    _requested = true;

    try {
      // 通知权限：所有版本都有用（下载进度通知）
      final PermissionStatus notif = await Permission.notification.status;
      if (notif == PermissionStatus.denied) {
        await Permission.notification.request();
      }

      // 媒体读取权限（Android 13+ 细化的 READ_MEDIA_*）：
      // 读取 Download 里的视频/音频需要（导入与离线列表场景）
      final PermissionStatus media = await Permission.mediaLibrary.status;
      if (media == PermissionStatus.denied) {
        await Permission.mediaLibrary.request();
      }

      // 存储权限：Android 10-12 走旧权限（华为 ROM 上缺了会下载失败）；
      // Android 13+ 该权限已被 READ_MEDIA_* 取代，request() 是 no-op。
      final PermissionStatus storage = await Permission.storage.status;
      if (storage == PermissionStatus.denied) {
        await Permission.storage.request();
      }
    } catch (_) {
      // 权限服务异常不阻塞启动（下载时会兜底再申请）
    }
  }
}
