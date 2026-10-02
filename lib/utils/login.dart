import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/init.dart';
import 'package:pilipala/http/user.dart';
import 'package:pilipala/pages/dynamics/index.dart';
import 'package:pilipala/pages/home/index.dart';
import 'package:pilipala/pages/media/index.dart';
import 'package:pilipala/pages/mine/index.dart';
import 'package:pilipala/pages/main/index.dart';
import 'package:pilipala/models/user/info.dart';
import 'package:pilipala/utils/blacklist_filter.dart';
import 'package:pilipala/utils/cookie.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:uuid/uuid.dart';

class LoginUtils {
  static Future<void> refreshLoginStatus(bool status) async {
    try {
      if (!status) {
        await GStrorage.userInfo.delete('userInfoCache');
        Request.setOptionsHeaders(null, false);
      }

      final cachedUser = GStrorage.userInfo.get('userInfoCache');
      final isLoggedIn = status &&
          cachedUser is UserInfoData &&
          cachedUser.isLogin == true &&
          cachedUser.mid != null;

      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().updateLoginStatus(isLoggedIn);
      }
      if (Get.isRegistered<MineController>()) {
        final mineCtr = Get.find<MineController>();
        mineCtr.userLogin.value = isLoggedIn;
        mineCtr.userInfo.value = isLoggedIn ? cachedUser : UserInfoData();
      }
      if (Get.isRegistered<DynamicsController>()) {
        Get.find<DynamicsController>().userLogin.value = isLoggedIn;
      }
      if (Get.isRegistered<MediaController>()) {
        final mediaCtr = Get.find<MediaController>();
        mediaCtr.userLogin.value = isLoggedIn;
        mediaCtr.mid = isLoggedIn ? cachedUser.mid : null;
      }
      if (Get.isRegistered<MainController>()) {
        Get.find<MainController>().userLogin.value = isLoggedIn;
      }

      // 登录态变化时同步服务端黑名单：刚登录/切换账号后，
      // 让搜索置顶 UP 卡等过滤立即拿到最新的黑名单数据
      if (isLoggedIn) {
        try {
          await BlacklistSync.refresh();
        } catch (_) {}
      } else {
        // 退出登录清空本地黑名单缓存，避免残留上个账号的拉黑数据
        await GStrorage.setting
            .put(SettingBoxKey.blackMidsList, <dynamic>[-1]);
        await GStrorage.setting.put(SettingBoxKey.blacklistNames, {});
        BlacklistUpdateBus.notify();
      }
    } catch (err) {
      SmartDialog.showToast('refreshLoginStatus error: ${err.toString()}');
    }
  }

  static String buvid() {
    var mac = <String>[];
    var random = Random();

    for (var i = 0; i < 6; i++) {
      var min = 0;
      var max = 0xff;
      var num = (random.nextInt(max - min + 1) + min).toRadixString(16);
      mac.add(num);
    }

    var md5Str = md5.convert(utf8.encode(mac.join(':'))).toString();
    var md5Arr = md5Str.split('');
    return 'XY${md5Arr[2]}${md5Arr[12]}${md5Arr[22]}$md5Str';
  }

  static String getUUID() {
    return const Uuid().v4().replaceAll('-', '');
  }

  static String generateBuvid() {
    String uuid = getUUID() + getUUID();
    return 'XY${uuid.substring(0, 35).toUpperCase()}';
  }

  static confirmLogin(url, controller) async {
    var content = '';
    if (url != null) {
      content = '${content + url}; \n';
    }
    try {
      await SetCookie.onSet();
      final result = await UserHttp.userInfo();
      if (result['status'] &&
          result['data'].isLogin == true &&
          result['data'].mid != null) {
        SmartDialog.showToast('登录成功');
        try {
          Box userInfoCache = GStrorage.userInfo;
          if (!userInfoCache.isOpen) {
            userInfoCache = await Hive.openBox('userInfo');
          }
          await userInfoCache.put('userInfoCache', result['data']);
          Request.setOptionsHeaders(result['data'], true);
          await LoginUtils.refreshLoginStatus(true);
        } catch (err) {
          SmartDialog.show(builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('登录遇到问题'),
              content: Text(err.toString()),
              actions: [
                TextButton(
                  onPressed: controller != null
                      ? () => controller.reload()
                      : SmartDialog.dismiss,
                  child: const Text('确认'),
                )
              ],
            );
          });
        }
        Get.back();
      } else {
        await GStrorage.userInfo.delete('userInfoCache');
        Request.setOptionsHeaders(null, false);
        SmartDialog.showToast(result['msg']);
      }
    } catch (e) {
      SmartDialog.showNotify(msg: e.toString(), notifyType: NotifyType.warning);
      content = content + e.toString();
      Clipboard.setData(ClipboardData(text: content));
    }
  }
}
