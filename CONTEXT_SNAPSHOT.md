# 会话关键上下文快照（context 压缩前）

## 项目
- pilipala fork (B站客户端), package com.Zeitlind.bill, 路径 E:\BILIGAI\pilipala
- 设备: 2KE5T19B16034402 (华为 EMUI, Android 12/13, targetSdk 33/34)
- flutter: /e/BILIGAI/tooling/flutter/bin/flutter
- 构建: cd /e/BILIGAI/pilipala && /e/BILIGAI/tooling/flutter/bin/flutter build apk --debug
- 安装: adb -s 2KE5T19B16034402 install -r build/app/outputs/flutter-apk/app-debug.apk
- adb 广播命令: adb shell am broadcast -a com.Zeitlind.bill.DEBUG_<CMD> [--es/--ei k v]
  - 注意: Git Bash 下路径参数（如 /playSetting）会被转成 Windows 路径导致参数丢失！
    必须用单引号整包: adb shell 'am broadcast -a ... --es route "/playSetting"'
- DebugBridge 命令: PING/GET_AUDIO_MODE/SET_AUDIO_MODE/GOTO_LIVE_ROOM/GOTO_VIDEO/
  GET_COMMENTS/GET_DANMAKU/GET_LIVE_DANMAKU/GET_CURRENT_STATE/GET_UI_TREE/TAP_NODE/
  SHOW_CONTROLS/SET_PLAYBACK_SPEED/GOTO_PAGE/SET_SIMPLE_MODE
- native 显式 action 列表在 MainActivity.kt（新增命令需同步加）

## 已完成功能（全部已安装）
1. 离线缓存: 弹幕/分段下载+本地播放+分段跳转+音频播放(OfflineAudioPage)+批量删除
2. 合集批量下载: SeasonPanel 批量下载按钮+多选+全选（跳回 bug 已修: jumpTo 只执行一次）
3. 后台下载: BatchDownloadService（lib/utils/batch_download_service.dart）
   - 前台/后台模式切换（进度弹窗含"后台下载"/"取消"按钮）
   - 通知栏进度条（原生 MainActivity.kt MethodChannel "com.Zeitlind.bill/download_notification",
     showProgress/done/cancel/startKeepAlive/stopKeepAlive/openBatterySettings/isIgnoringBatteryOptimizations）
   - DownloadForegroundService: 前台服务+PARTIAL_WAKE_LOCK 保活（Kotlin+manifest dataSync 类型）
   - Dio 断点续传+网络错误重试（5次退避 2/4/8/16s）
   - 电池优化白名单引导弹窗
4. 批量取关: UnfollowService + 关注列表多选 + UnfollowSettingPage（规则: 等长/间歇/随机）
5. 批量移除收藏: UnfavService + fav_detail 多选 + UnfavSettingPage（保存到 Zeitlind/danmaku/yyyy-mm-dd.txt）
6. 极简模式: SimpleModeService（开关+定时开关）+ 底栏去动态/排行榜 + 首页收藏夹 tab
   + 搜索页禁热搜/历史/联想

## 当前任务（进行中）
- 【黑屏卡死根因】锁屏时 Flutter 主 isolate 被 EMUI 冻结→回前台时积压数据一次性涌入
  → 主线程阻塞 47.5 秒（主线程心跳日志证实），Dart 事件循环卡死（resumed 后 frame-marker 无一按时执行）
- 【已做重构】BatchDownloadService 整个下载循环移到独立 isolate（Isolate.spawn _workerMain）:
  - worker 经 SendPort 回报 progress/itemDone/done/port 消息
  - 主 isolate 只做 UI（弹窗/通知）
  - 文件: lib/utils/batch_download_service.dart（已重写完成，analyze 0 错误）
  - MediaDownloadService.downloadVideo 加了 silent/onProgress 参数（静默模式不弹 UI）
- 【当前卡点】正在设备上自动验证 isolate 版下载是否工作:
  - 触发方式: 视频页 header 下载按钮（x~985,y~160）→ 下载面板 → 点"下载视频"选项
  - 下载面板选项的精确坐标还没点中（试过 1820/1900/2000 都无 BatchDownload 日志）
  - 面板结构: y1610-1670 第一项(音频), y1940-2060 第二项(视频)（亮度边界分析）
- 【诊断工具仍生效】主线程心跳（PiliLifecycle tag，阻塞>1300ms 转储栈）
  + black_screen_log.txt（Download/Zeitlind/ 下，lifecycle+resumed tick 持久化）

## 下一步
1. 设备验证 isolate 版下载：继续定位下载面板"下载视频"精确坐标（面板第一项 y~1610-1910 是音频，
   第二项 y~1940-2240 是视频——但 tap 2000 无日志，需截图确认面板实际内容）
2. 若 worker isolate 有异常（如 Hive/GetX 在 isolate 内不可用的崩溃）会体现在日志
3. 验证: 下载成功→锁屏→回前台→确认不再卡死
4. 完成后删除诊断日志代码（PiliLifecycle 心跳/black_screen_log）

## 关键文件
- lib/utils/batch_download_service.dart (isolate 重构版)
- lib/utils/media_download.dart (silent/onProgress 参数+Dio 断点续传重试)
- lib/utils/download_notification.dart (通知封装)
- lib/utils/unfollow_service.dart / unfav_service.dart / simple_mode_service.dart
- lib/common/pages_bottom_sheet.dart (合集面板+多选)
- lib/pages/follow/ lib/pages/fav_detail/ lib/pages/offline_cache/
- android/.../MainActivity.kt (通知+保活+生命周期日志+心跳)
- android/.../DownloadForegroundService.kt
- lib/pages/setting/unfollow_setting.dart / unfav_setting.dart

## 用户敏感约束
- 批量取关/批量移除收藏/批量下载属于敏感操作: 只编译安装，不代用户执行真实操作
- 普通下载/锁屏测试可以自动验证
