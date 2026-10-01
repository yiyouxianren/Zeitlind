import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/utils/download_logger.dart';
import 'package:pilipala/utils/download_notification.dart';
import 'package:pilipala/utils/id_utils.dart';
import 'package:pilipala/utils/media_download.dart';
import 'package:pilipala/utils/offline_attachments.dart';

/// 合集/单视频批量下载服务：队列 + 后台 isolate 下载 + 可切后台
///
/// 下载循环跑在独立 isolate：
/// - 锁屏/回前台时 UI isolate 被冻结不再影响下载
/// - 回前台唤醒时没有积压数据涌入主线程（解决黑屏卡死）
/// - 进度通过 SendPort 回主 isolate，仅用于弹窗/通知展示
class BatchDownloadService extends GetxService with WidgetsBindingObserver {
  static BatchDownloadService get instance => Get.find<BatchDownloadService>();

  /// 下载队列：{bvid, cid, title}（镜像 worker 内队列，用于 UI 计数）
  final RxList<Map<String, dynamic>> queue = <Map<String, dynamic>>[].obs;

  final RxBool running = false.obs;

  /// 是否处于后台模式（隐藏进度 UI 但继续下载）
  final RxBool backgroundMode = false.obs;

  /// 当前进度文案（前台弹窗与后台查询共用）
  final RxString currentMsg = ''.obs;

  final RxInt okCount = 0.obs;
  final RxInt failCount = 0.obs;

  int _initialTotal = 0;
  Isolate? _worker;
  ReceivePort? _receivePort;
  SendPort? _toWorker;
  DateTime? _pausedAt;

  static const String _tag = 'batchDownload';

  /// 加入队列并启动（若未运行）
  void enqueue(List<Map<String, dynamic>> items) {
    DownloadLogger.log('[service] enqueue called, items=${items.length}');
    if (running.value) {
      // 旧实现会把未预解析的任务直接发给 worker（worker 无法访问网络/
      // Hive 单例），导致序号错乱与连环失败。改为排队：本轮结束后由
      // _finish 自动接续下一批（预解析在主 isolate 重新走 _start 流程）。
      DownloadLogger.log('[service] enqueue while running -> queued for next round');
      final existing = queue.map((e) => e['cid']).toSet();
      for (final it in items) {
        if (!existing.contains(it['cid'])) queue.add(it);
      }
      _initialTotal += items.length;
      SmartDialog.showToast(
          '已加入队列：当前批次完成后自动开始（共 ${queue.length} 个待下载）');
      return;
    }
    final existing = queue.map((e) => e['cid']).toSet();
    for (final it in items) {
      if (!existing.contains(it['cid'])) queue.add(it);
    }
    DownloadLogger.log('[service] queue now=${queue.length} '
        'running=${running.value} toWorker=${_toWorker != null}');
    if (queue.isNotEmpty) {
      _start();
    }
  }

  Future<void> _start() async {
    DownloadLogger.log('[service] _start begin, total=${queue.length}');
    running.value = true;
    // 轮次状态复位：_workerDone/_mergeRunning 是上一轮的残留值，
    // 不清零会导致上一轮 done 已置 true → 本轮 worker 未结束也"已完成"，
    // merge 收尾判断错乱（本轮卡在「合并 MP4 中」不弹完成）。
    _workerDone = false;
    _mergeRunning = false;
    _mergeQueue.clear();
    _pendingMerges.clear();
    // 看门狗与结算表同样按轮清零
    for (final Timer t in _mergeWatchdogs.values) {
      t.cancel();
    }
    _mergeWatchdogs.clear();
    _watchdogResolved.clear();
    // 轮次总看门狗：单任务看门狗只盯单个 merge 的文件生成，但实测还存在
    // mergeDone ok=true 打出后 _finish 仍不执行的路径（_finish 内弹窗/
    // 通知 await 抛异常会中断整条 async 链）。总看门狗兜底：running 期间
    // 每 30s 检查一次，若"无待合并任务且 worker 已结束"超过 90 秒仍
    // running=true，强制收尾（幂等守卫防重入）。
    _roundWatchdog?.cancel();
    _roundWatchdog = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!running.value) {
        _roundWatchdog?.cancel();
        _roundWatchdog = null;
        return;
      }
      final bool idle = _pendingMerges.isEmpty &&
          _mergeQueue.isEmpty &&
          !_mergeRunning &&
          _workerDone;
      if (idle) {
        _idleTicks++;
        if (_idleTicks >= 3) {
          DownloadLogger.log('[roundWatchdog] idle 90s while running '
              '-> force finish');
          _roundWatchdog?.cancel();
          _roundWatchdog = null;
          _finish(false);
        }
      } else {
        _idleTicks = 0;
      }
    });
    _idleTicks = 0;
    backgroundMode.value = false;
    okCount.value = 0;
    failCount.value = 0;
    _initialTotal = queue.length;
    SmartDialog.showToast(
        _initialTotal > 1 ? '开始批量下载：$_initialTotal 个视频' : '开始下载');
    // 前台服务 + WakeLock：后台/锁屏时保持下载
    DownloadLogger.log('[service] keepAlive starting');
    DownloadNotification.startKeepAlive();
    _showProgress();

    // 下载前省电策略守门：华为设备后台受限时锁屏下载会被系统冻结，
    // 先引导用户去「应用启动管理」关闭自动管理（=无限制），确认后才继续
    final bool policyOk = await _ensurePowerPolicy();
    if (!policyOk) {
      DownloadLogger.log('[service] ABORT: battery policy restricted, user went to settings');
      await _finish(false);
      return;
    }

    // 轮次开始：清空上一轮残留的轨道临时文件（此刻既无进行中下载也无
    // 待合并轨道，清理安全；worker 内不再做跨 cid 清理——它看不到主
    // isolate 的合并排队状态，误删会导致 ffmpeg No such file）
    MediaDownloadService.cleanupAllTempTracks();

    // 预解析阶段（主 isolate）：查 DASH、选轨、读设置——
    // VideoHttp/Request/Hive 单例只在主 isolate 可用，必须在这里完成。
    final List<Map<String, dynamic>> resolvedItems = [];
    final List<Map<String, dynamic>> failedItems = [];
    for (final item in queue) {
      final MediaDownloadPlan? plan = await MediaDownloadService.resolvePlan(
        bvid: item['bvid'],
        cid: item['cid'],
        preferredVideoQa: item['videoQa'],
        preferredDecode: item['decode'],
        toast: _initialTotal == 1 ? (m) => SmartDialog.showToast(m) : null,
      );
      if (plan != null) {
        resolvedItems.add({...item, 'plan': plan});
      } else {
        failedItems.add(item);
      }
    }
    DownloadLogger.log('[service] resolve done: ok=${resolvedItems.length} '
        'fail=${failedItems.length}');
    // 同名跳过：该标题的视频文件已存在于 Download/Zeitlind/Video（含
    // 用户手动导入的旧缓存）时不再重复下载视频轨道，但弹幕/分段附属
    // 文件仍按需刷新（旧附属缺失/损坏/旧版本下载的都补齐）。
    final List<Map<String, dynamic>> skipped =
        resolvedItems.where((it) => MediaDownloadService
                .isVideoDownloaded((it['title'] ?? '') as String))
            .toList();
    if (skipped.isNotEmpty) {
      resolvedItems.removeWhere((it) => skipped.contains(it));
      queue.removeWhere((e) => skipped.any((s) => s['cid'] == e['cid']));
      for (final it in skipped) {
        DownloadLogger.log('[service] SKIP video, refresh attachments: '
            'cid=${it['cid']} title=${it['title']}');
      }
      // 附属刷新走主 isolate（网络请求经 Request 单例），
      // 不进 worker，也不占进度弹窗。
      unawaited(_refreshAttachmentsFor(skipped));
      SmartDialog.showToast(
          '${skipped.length} 个视频已缓存过，跳过下载并刷新弹幕/分段');
    }
    if (failedItems.isNotEmpty) {
      failCount.value += failedItems.length;
      queue.removeWhere((e) => failedItems.any((f) => f['cid'] == e['cid']));
      if (_initialTotal == 1) {
        // 单个任务且预解析失败：直接收尾（弹窗已由 resolvePlan 的 toast 提示）
        await _finish(false);
        return;
      }
      if (resolvedItems.isEmpty) {
        SmartDialog.showToast('批量下载预解析失败：${failedItems.length} 个');
        await _finish(false);
        return;
      }
    }

    // 启动下载 isolate（纯 Dio 下载 + ffmpeg 合并在 worker 内完成）
    _receivePort = ReceivePort();
    _receivePort!.listen(_handleWorkerMessage);
    DownloadLogger.log('[service] spawning worker isolate');
    try {
      await Isolate.spawn(
        _workerMain,
        _WorkerConfig(
          sendPort: _receivePort!.sendPort,
          items: resolvedItems,
          logPath: DownloadLogger.filePath,
        ),
        debugName: 'batch-download',
      );
      DownloadLogger.log('[service] worker spawned ok');
    } catch (e, st) {
      // isolate 启动失败：直接结束本轮并提示（否则弹窗永远停在“准备中”）
      DownloadLogger.log('[service] worker spawn FAILED: $e');
      DownloadLogger.log('[service] spawn stack: ${st.toString().split('\n').take(8).join(' | ')}');
      running.value = false;
      _worker = null;
      _toWorker = null;
      _receivePort?.close();
      _receivePort = null;
      SmartDialog.dismiss(tag: _tag);
      SmartDialog.showToast('下载启动失败：$e');
      DownloadNotification.stopKeepAlive();
    }
  }

  /// 单个视频的附属刷新（对外入口：播放页"已缓存过"时调用）。
  /// 查询 DASH 拿时长后走 OfflineAttachments.downloadAll；
  /// 附属已齐全则不做任何网络请求。
  Future<void> refreshAttachments({
    required String bvid,
    required int cid,
    required String title,
  }) async {
    try {
      final String safeTitle = MediaDownloadService.sanitizeTitle(title);
      final bool dmOk = await OfflineAttachments.hasDanmakuFile(safeTitle);
      final bool vpOk = await OfflineAttachments.hasViewPointsFile(safeTitle);
      if (dmOk && vpOk) {
        DownloadLogger.log('[refreshAttachments] intact, skip cid=$cid');
        return;
      }
      final MediaDownloadPlan? plan = await MediaDownloadService.resolvePlan(
        bvid: bvid,
        cid: cid,
        toast: null,
      );
      if (plan == null) return;
      final Duration? duration = plan.dashDurationMs != null &&
              plan.dashDurationMs! > 0
          ? Duration(milliseconds: plan.dashDurationMs!)
          : null;
      if (duration == null) return;
      await OfflineAttachments.downloadAll(
        bvid: bvid,
        cid: cid,
        aid: IdUtils.bv2av(bvid),
        safeTitle: safeTitle,
        videoDuration: duration,
      );
      DownloadLogger.log('[refreshAttachments] refreshed cid=$cid '
          'title=$safeTitle (dm=$dmOk vp=$vpOk)');
    } catch (e) {
      DownloadLogger.log('[refreshAttachments] FAILED cid=$cid: $e');
    }
  }

  /// 为"视频已存在、跳过下载"的条目刷新附属文件（弹幕 .dm / 分段 .vp.json）。
  /// 场景：旧版本下载的缓存没有附属文件，或附属损坏——重下时补齐，
  /// 但不重下视频本体。静默执行，不打断进度 UI。
  Future<void> _refreshAttachmentsFor(List<Map<String, dynamic>> items) async {
    int refreshed = 0;
    for (final it in items) {
      try {
        final MediaDownloadPlan? plan = it['plan'] is MediaDownloadPlan
            ? it['plan'] as MediaDownloadPlan
            : null;
        final String title = (it['title'] ?? '') as String;
        final String bvid = it['bvid'] as String;
        final int cid = it['cid'] as int;
        if (plan == null) continue;
        final String safeTitle = MediaDownloadService.sanitizeTitle(title);
        final bool dmOk = await OfflineAttachments.hasDanmakuFile(safeTitle);
        final bool vpOk = await OfflineAttachments.hasViewPointsFile(safeTitle);
        if (dmOk && vpOk) {
          // 附属齐全：无需刷新
          DownloadLogger.log('[refreshAttachments] intact, skip cid=$cid');
          continue;
        }
        final Duration? duration = plan.dashDurationMs != null &&
                plan.dashDurationMs! > 0
            ? Duration(milliseconds: plan.dashDurationMs!)
            : null;
        if (duration == null) continue;
        await OfflineAttachments.downloadAll(
          bvid: bvid,
          cid: cid,
          aid: IdUtils.bv2av(bvid),
          safeTitle: safeTitle,
          videoDuration: duration,
        );
        refreshed++;
        DownloadLogger.log('[refreshAttachments] refreshed cid=$cid '
            'title=$safeTitle (dm=$dmOk vp=$vpOk)');
      } catch (e) {
        DownloadLogger.log('[refreshAttachments] FAILED cid=${it['cid']}: $e');
      }
    }
    if (refreshed > 0) {
      DownloadLogger.log('[refreshAttachments] done, $refreshed refreshed');
    }
  }

  /// 转后台：隐藏进度弹窗，下载不中断
  void toBackground() {
    backgroundMode.value = true;
    SmartDialog.dismiss(tag: _tag);
    SmartDialog.showToast(queue.length > 1
        ? '已转入后台下载：剩余 ${queue.length} 个，可继续浏览其它页面'
        : '已转入后台下载，可继续浏览其它页面');
  }

  /// 恢复前台进度弹窗
  void toForeground() {
    if (!running.value) return;
    backgroundMode.value = false;
    _showProgress();
  }

  /// 取消剩余任务
  void cancel() {
    SmartDialog.dismiss(status: SmartStatus.smart);
    SmartDialog.showToast('已取消：剩余 ${queue.length} 个不再下载');
    DownloadNotification.cancel();
      _toWorker?.send({'type': 'cancel'});
      // 合并中/待合并任务一并作废，让 done 消息能正常收尾
      _pendingMerges.clear();
      _mergeQueue.clear();
      MediaDownloadService.mergingCids.clear();
    queue.clear();
  }

  void _showProgress() {
    SmartDialog.show(
      tag: _tag,
      builder: (BuildContext context) {
        return Obx(() => AlertDialog(
              title: Text(_initialTotal > 1
                  ? '批量下载中（${okCount.value + failCount.value}/$_initialTotal）'
                  : '视频下载'),
              content: Text(
                  currentMsg.value.isEmpty ? '准备中...' : currentMsg.value),
              actions: [
                TextButton(
                  onPressed: () => toBackground(),
                  child: const Text('后台下载'),
                ),
                TextButton(
                  onPressed: () => cancel(),
                  child: const Text('取消'),
                ),
              ],
            ));
      },
    );
  }

  /// 主 isolate：处理 worker 回报
  void _handleWorkerMessage(dynamic msg) {
    if (msg is! Map) return;
    if (msg['type'] != 'progress') {
      // progress 消息高频，不逐条落盘
      DownloadLogger.log('[service] worker msg: ${msg['type']}'
          '${msg['type'] == 'itemDone' ? ' ok=${msg['ok']} cid=${msg['cid']}' : ''}');
    }
    switch (msg['type']) {
      case 'port':
        _toWorker = msg['port'] as SendPort;
        break;
      case 'progress':
        currentMsg.value = msg['msg'] as String;
        final int? percent = msg['percent'] as int?;
        final int done = okCount.value + failCount.value;
        DownloadNotification.showProgress(
          title: _initialTotal > 1
              ? '批量下载 (${done + 1}/$_initialTotal)'
              : '视频下载',
          text: '${msg['title']} · ${msg['msg']}',
          progress: percent,
        );
        break;
      case 'itemDone':
        (msg['ok'] as bool) ? okCount.value++ : failCount.value++;
        queue.removeWhere((e) => e['cid'] == msg['cid']);
        break;
      case 'merge':
        // worker 已把轨道下齐，主 isolate 执行 FFmpeg 合并（插件限制：
        // 原生完成回调只能回主 isolate，worker 里跑会闪退）
        unawaited(_mergeOnMain(msg));
        break;
      case 'done':
        // worker 已结束；若还有待合并/合并中任务，等最后一个 merge 完成收尾
        // （merge 队列可能尚未把 cid 加入 _pendingMerges，两个集合都要看）。
        _workerDone = true;
        if (_pendingMerges.isEmpty && _mergeQueue.isEmpty && !_mergeRunning) {
          DownloadLogger.log('[service] done -> tryFinish');
          unawaited(_finish(msg['canceled'] as bool? ?? false));
        } else {
          DownloadLogger.log('[service] done msg deferred, '
              'pendingMerges=${_pendingMerges.length} queued=${_mergeQueue.length}');
        }
        break;
      case 'log':
        debugPrint('BatchDownload[worker]: ${msg['msg']}');
        break;
    }
  }

  final Set<int> _pendingMerges = <int>{};
  bool _workerDone = false;

  Future<void> _mergeOnMain(Map<dynamic, dynamic> msg) async {
    // 串行合并：FFmpegKit 同时跑多个 session 会互相抢 IO/CPU（每个内部都
    // 有 100ms 轮询定时器），锁屏+并发合并时主 isolate 事件循环被拖死。
    // merge 队列按到达顺序依次执行。
    _mergeQueue.add(msg);
    if (_mergeRunning) return;
    _mergeRunning = true;
    try {
      while (_mergeQueue.isNotEmpty) {
        await _doMerge(_mergeQueue.removeAt(0));
      }
    } catch (e, st) {
      // _doMerge 内任何异常都会中断整条合并循环（finally 只复位标志，
      // 不结算任务）→ 队列里剩余任务永远无人处理，弹窗卡死。这里兜底：
      // 把剩余未结算的 merge 全部按失败清出队列，保证轮次能收尾。
      DownloadLogger.log('[service] merge loop CRASH: $e');
      DownloadLogger.log('[service] merge loop stack: '
          '${st.toString().split('\n').take(6).join(' | ')}');
      for (final m in List<Map<dynamic, dynamic>>.from(_mergeQueue)) {
        final int c = m['cid'] as int;
        _stopMergeWatchdog(_mergeWatchdogs[c], c, 'merge-loop-crash');
        _resolveHungMerge(c, false);
        _mergeQueue.removeWhere((e) => e['cid'] == c);
      }
    } finally {
      _mergeRunning = false;
    }
    // 循环退出后兜底检查收尾：done 消息可能在合并期间到达（deferred），
    // 而 _doMerge 内的 tryFinish 日志证明它偶尔不触发——这里从合并循环
    // 侧再补一次，双保险确保收尾不丢。
    if (_workerDone && _pendingMerges.isEmpty && _mergeQueue.isEmpty) {
      DownloadLogger.log('[service] merge loop exit -> tryFinish');
      unawaited(_finish(false));
    }
  }

  final List<Map<dynamic, dynamic>> _mergeQueue = <Map<dynamic, dynamic>>[];
  bool _mergeRunning = false;

  Future<void> _doMerge(Map<dynamic, dynamic> msg) async {
    final int cid = msg['cid'] as int;
    final MediaDownloadPlan plan = msg['plan'] as MediaDownloadPlan;
    _pendingMerges.add(cid);
    // 登记合并保护：worker 下载后续视频时的临时清理不得删本 cid 的轨道
    MediaDownloadService.mergingCids.add(cid);
    currentMsg.value = '合并 MP4 中';
    // 通知走 fire-and-forget：MethodChannel invoke 返回的 future 若被
    // await，通道异常/ROM 冻结会挂起整条 _doMerge 链
    unawaited(DownloadNotification.showProgress(
      title: _initialTotal > 1 ? '批量下载' : '视频下载',
      text: '${msg['title']} · 合并 MP4 中',
      progress: null,
    ));
    // 保底看门狗：FFmpegKit 的 MethodChannel 回调若丢失（华为 ROM 低内存
    // 回收插件会话等），await mergeTracks 会永远挂起，弹窗卡死在
    // 「合并 MP4 中」。看门狗周期性检查输出文件是否已实际生成：
    // - 生成 → 文件级证据表明合并已完成，直接按成功收尾（解除死锁）
    // - 连续 20 次未生成 → 放弃本任务，按失败收尾，继续下一个
    final String title = msg['title'] as String? ?? '';
    final String outputPath = MediaDownloadService.videoOutputPath(title);
    final DateTime mergeStartedAt = DateTime.now();
    Timer watchdog = _startMergeWatchdog(
        cid, title, outputPath, mergeStartedAt);
    final bool ok = await MediaDownloadService.mergeTracks(
      cid: cid,
      bvid: msg['bvid'] as String,
      title: title,
      plan: plan,
      hasAudio: plan.audioUrl != null,
      tmpVideo: '',
      tmpAudio: '',
      silent: true,
      onProgress: (m) {
        currentMsg.value = m;
      },
    );
    _stopMergeWatchdog(watchdog, cid, 'normal-done ok=$ok');
    // 看门狗可能已抢先结算本 cid（回调丢失场景）：跳过重复计数
    if (_watchdogResolved.remove(cid)) {
      DownloadLogger.log('[service] mergeDone cid=$cid already resolved by '
          'watchdog, skip duplicate accounting');
      return;
    }
    _pendingMerges.remove(cid);
    MediaDownloadService.mergingCids.remove(cid); // 轨道已消费/清理，解除保护
    ok ? okCount.value++ : failCount.value++;
    queue.removeWhere((e) => e['cid'] == cid);
    DownloadLogger.log('[service] mergeDone cid=$cid ok=$ok '
        'pendingMerges=${_pendingMerges.length} running=${running.value}');
    // ★ 收尾条件绝不能包含 queue.isEmpty：运行中入队的新任务躺在 queue 里
    // 等下一轮（由 _finish 的 auto-start 接续），它们的存在不能阻塞本轮
    // 收尾——否则互相死锁：队列非空 → 本轮不结束 → 下一轮永不开始，
    // 弹窗永远停在「合并 MP4 中」。
    if (_workerDone && _pendingMerges.isEmpty && _mergeQueue.isEmpty && !_mergeRunning) {
      DownloadLogger.log('[service] mergeDone -> tryFinish');
      // fire-and-forget：不让 _doMerge 链再挂起在收尾的任何 await 上
      unawaited(_finish(false));
    }
  }

  // ---------- 合并看门狗（保底逻辑） ----------

  /// 挂起的 mergeTracks 的看门狗表（cid -> timer）。
  final Map<int, Timer> _mergeWatchdogs = <int, Timer>{};

  /// 轮次总看门狗与空转计数
  Timer? _roundWatchdog;
  int _idleTicks = 0;

  /// 启动看门狗：每 6 秒检查一次（约 1 分钟起效，最多 20 次检查）。
  Timer _startMergeWatchdog(
      int cid, String title, String outputPath, DateTime startedAt) {
    int checks = 0;
    final Timer t = Timer.periodic(const Duration(seconds: 6), (_) async {
      checks++;
      final bool exists = await File(outputPath).exists();
      final int ageSec = DateTime.now().difference(startedAt).inSeconds;
      DownloadLogger.log('[watchdog] cid=$cid check#$checks '
          'exists=$exists age=${ageSec}s');
      // 1 分钟内给正常合并留时间（大文件合并可能需要 1-2 分钟）
      if (ageSec < 60) return;
      if (exists) {
        // 文件已生成：合并实际成功，只是回调丢失。解除挂起的 await
        // 不可行（Future 无法外部 complete），改为直接收尾本任务：
        // 计数 + 清队 + 必要时 _finish。挂起的 _doMerge 之后即使醒来，
        // 其重复计数由 _finishOnce 守卫挡住。
        DownloadLogger.log('[watchdog] cid=$cid OUTPUT EXISTS -> '
            'finish as success (merge callback lost)');
        _stopMergeWatchdog(_mergeWatchdogs[cid], cid, 'watchdog-success');
        _resolveHungMerge(cid, true);
      } else if (checks >= 20) {
        // 连续 20 次未生成：终止本任务，继续下一个
        DownloadLogger.log('[watchdog] cid=$cid NO OUTPUT after 20 checks '
            '-> abandon, continue next');
        _stopMergeWatchdog(_mergeWatchdogs[cid], cid, 'watchdog-abandon');
        _resolveHungMerge(cid, false);
      }
    });
    _mergeWatchdogs[cid] = t;
    return t;
  }

  void _stopMergeWatchdog(Timer? t, int cid, String reason) {
    t?.cancel();
    _mergeWatchdogs.remove(cid);
    DownloadLogger.log('[watchdog] cid=$cid stopped: $reason');
  }

  /// 看门狗判定合并死锁后的收尾（成功/失败）。
  /// 幂等守卫：_doMerge 正常醒来后若发现本 cid 已被看门狗结算，跳过重复计数。
  final Set<int> _watchdogResolved = <int>{};

  void _resolveHungMerge(int cid, bool ok) {
    if (_watchdogResolved.contains(cid)) return;
    _watchdogResolved.add(cid);
    _pendingMerges.remove(cid);
    MediaDownloadService.mergingCids.remove(cid);
    ok ? okCount.value++ : failCount.value++;
    queue.removeWhere((e) => e['cid'] == cid);
    currentMsg.value = ok ? '下载完成' : '合并超时，已跳过';
    DownloadLogger.log('[service] watchdogResolved cid=$cid ok=$ok');
    if (_workerDone && _pendingMerges.isEmpty && _mergeQueue.isEmpty && !_mergeRunning) {
      unawaited(_finish(false));
    }
  }

  Future<void> _finish(bool canceled) async {
    // 幂等守卫：_finish 可能被 mergeDone/done/轮次看门狗多条路径触发，
    // 且 running=false 只在本方法置位——用独立标志防重入（防弹窗重复/计数错乱）
    if (_finishing) {
      DownloadLogger.log('[service] finish REJECTED (already finishing)');
      return;
    }
    _finishing = true;
    DownloadLogger.log('[service] finish, canceled=$canceled '
        'ok=${okCount.value} fail=${failCount.value}');
    _roundWatchdog?.cancel();
    _roundWatchdog = null;
    try {
    await _finishBody(canceled);
    } catch (e) {
      DownloadLogger.log('[service] finish BODY ERROR: $e');
    } finally {
      _finishing = false;
    }
  }

  bool _finishing = false;

  Future<void> _finishBody(bool canceled) async {
    running.value = false;
    final ok = okCount.value;
    final fail = failCount.value;
    final single = _initialTotal <= 1;
    currentMsg.value = '';
    _worker = null;
    _toWorker = null;
    _receivePort?.close();
    _receivePort = null;
    // 本轮所有合并都已收尾（done 分支保证），保护集/看门狗/结算表清空防泄漏
    MediaDownloadService.mergingCids.clear();
    for (final Timer t in _mergeWatchdogs.values) {
      t.cancel();
    }
    _mergeWatchdogs.clear();
    _watchdogResolved.clear();
    final bool hasQueued = queue.isNotEmpty;
    // ★ 所有 UI/通知交互全部 fire-and-forget + 独立 try-catch：
    // 这些调用任何一次挂起（SmartDialog 内部 await toast 队列、
    // MethodChannel 通道冻结）都不再能阻塞或中断收尾流程。
    // 这是"mergeDone 已打出但 _finish 没执行"的根治点。
    runZonedGuarded(() {
      if (!backgroundMode.value) {
        SmartDialog.dismiss(tag: _tag);
      }
      SmartDialog.dismiss(status: SmartStatus.smart);
      SmartDialog.showToast(single
          ? (canceled ? '下载已取消' : (ok > 0 ? '下载完成' : '下载失败'))
          : (canceled ? '批量下载已取消：完成 $ok，失败 $fail' : '批量下载完成：成功 $ok，失败 $fail'));
    }, (e, st) {
      DownloadLogger.log('[service] finish UI error: $e');
    });
    unawaited(DownloadNotification.done(
      title: single
          ? (canceled ? '下载已取消' : '下载完成')
          : (canceled ? '批量下载已取消' : '批量下载完成'),
      text: '成功 $ok，失败 $fail',
    ).catchError((e) {
      DownloadLogger.log('[service] finish notif error: $e');
    }));
    unawaited(DownloadNotification.stopKeepAlive().catchError((e) {
      DownloadLogger.log('[service] keepAlive stop error: $e');
    }));
    DownloadLogger.log('[service] finishBody core done, hasQueued=$hasQueued');

    // 排队任务接续：上一轮结束后自动开启下一批（含 enqueue-while-running
    // 暂存的任务），不再需要杀进程重试
    if (!canceled && hasQueued) {
      DownloadLogger.log('[service] pending queue=${queue.length}, auto start next round');
      await Future<void>.delayed(const Duration(seconds: 2));
      if (queue.isNotEmpty && !running.value) {
        _start();
      }
    }
  }

  /// 下载前省电策略守门：每次下载前查询后台策略。
  /// - unrestricted：直接放行
  /// - restricted/unknown（或未忽略电池优化）：弹窗引导去设置；
  ///   用户点「去设置」则中断本次下载（回来后重新点下载即续传），
  ///   点「继续下载」则照常下载（用户明确知情）
  /// 引导只在每次下载前触发一次（SmartDialog tag 防重复）。
  Future<bool> _ensurePowerPolicy() async {
    final String policy = await DownloadNotification.getPowerSavePolicy();
    final bool ignoring =
        await DownloadNotification.isIgnoringBatteryOptimizations();
    DownloadLogger.log('[service] power policy=$policy '
        'ignoringBatteryOpt=$ignoring');
    if (policy == 'unrestricted' && ignoring) return true;

    final Completer<bool> decision = Completer<bool>();
    // 用普通 Flutter 弹窗（与进度弹窗同队列）。不要用 useSystem: true——
    // EMUI 上系统级弹窗不渲染且 dismiss 异常会炸掉整条 async 链。
    SmartDialog.show(
      tag: 'powerPolicy',
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('需要允许后台运行'),
          content: const Text(
              '检测到本应用的后台运行受限，锁屏或退到后台时下载会被系统中断。\n\n'
              '请在系统设置中：\n'
              '1. 华为设备：应用启动管理 → 找到本应用 → 关闭「自动管理」，'
              '并允许后台活动\n'
              '2. 其他设备：电池优化 → 允许本应用（无限制）\n\n'
              '设置完成后回来重新点击下载，已下载的部分会自动续传。'),
          actions: [
            TextButton(
              onPressed: () {
                _closePolicyDialog();
                if (!decision.isCompleted) decision.complete(false);
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                _closePolicyDialog();
                if (!decision.isCompleted) decision.complete(true);
              },
              child: const Text('继续下载'),
            ),
            FilledButton(
              onPressed: () {
                _closePolicyDialog();
                DownloadNotification.openHuaweiAppLaunchSettings();
                if (!decision.isCompleted) decision.complete(false);
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
    DownloadLogger.log('[service] power policy dialog shown, waiting user');
    // 用户 60 秒未操作则默认放行（避免卡在"准备中"）
    final bool ok = await decision.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        // 日志先行：dismiss 抛异常也不能吞掉放行结果
        DownloadLogger.log('[service] power policy dialog timeout, continue');
        _closePolicyDialog();
        return true;
      },
    );
    return ok;
  }

  void _closePolicyDialog() {
    try {
      SmartDialog.dismiss(tag: 'powerPolicy');
    } catch (e) {
      DownloadLogger.log('[service] dismiss powerPolicy error: $e');
    }
  }

  // ---------- lifecycle 观测（黑屏诊断日志持久化） ----------

  /// 黑屏/卡顿记录持久化（logcat 可能滚掉）
  void _logToFile(String msg) {
    try {
      final File f =
          File('/storage/emulated/0/Download/Zeitlind/black_screen_log.txt');
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $msg\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final String msg = 'lifecycle $state '
        '(paused ${_pausedAt != null ? DateTime.now().difference(_pausedAt!).inSeconds : 0}s ago) '
        'running=${running.value} bg=${backgroundMode.value}';
    debugPrint('BatchDownload: $msg');
    _logToFile(msg);
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      scheduleMicrotask(() async {
        for (int i = 1; i <= 3; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          debugPrint('BatchDownload: resumed+${i}s frame-marker tick');
          _logToFile('resumed+${i}s tick');
        }
      });
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _worker?.kill();
    _receivePort?.close();
    super.onClose();
  }
}

class _WorkerConfig {
  final SendPort sendPort;
  final List<Map<String, dynamic>> items;
  final String logPath;
  _WorkerConfig({
    required this.sendPort,
    required this.items,
    required this.logPath,
  });
}

/// 下载 isolate 入口：与 UI isolate 完全隔离。
/// 注意：isolate 内不能访问 GetX/Hive 单例，所需数据全部经 config 传入。
/// ★ worker 必须保持"哑化"：绝不调用 BackgroundIsolateBinaryMessenger
/// .ensureInitialized、绝不使用任何插件通道。原因：ensureInitialized 会把
/// ffmpeg_kit 插件的 MethodChannel response 端口绑到本 worker 的
/// ReceivePort；主 isolate 后续执行 FFmpeg 合并时，原生完成回调的
/// response 仍发往 worker 端口（无论 worker 是否退出）→ engine
/// platform_message_response did_send 断言 → 整个 APP 闪退。
/// worker 只做纯 Dart 的工作（Dio 下载 + dart:io 文件操作），不需要通道。
/// 进度回调节流：Dio 的 onReceiveProgress 每秒可触发上百次，原样转发会给
/// 主 isolate 每次都排一个 platform 线程任务（通知更新 + Rx 刷新），锁屏
/// 期间任务积压，亮屏后主线程被串行灌入 → 1.5~6 秒/次的阻塞（黑屏）。
/// 改为最短 500ms 一条，且仅百分比变化时发送。
void Function(String msg) _throttledProgress(SendPort toMain, String title) {
  int lastSentMs = 0;
  int? lastPercent;
  return (String msg) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final RegExpMatch? m = RegExp(r'(\d+)%').firstMatch(msg);
    final int? percent = m != null ? int.tryParse(m.group(1)!) : null;
    if (now - lastSentMs < 500 && percent == lastPercent) return;
    lastSentMs = now;
    lastPercent = percent;
    toMain.send({
      'type': 'progress',
      'msg': msg,
      'percent': percent,
      'title': title,
    });
  };
}

Future<void> _workerMain(_WorkerConfig config) async {
  // worker 与主 isolate 写同一个日志文件
  DownloadLogger.usePath(config.logPath);
  DownloadLogger.log('[worker] isolate alive (dumb mode, no plugin channels), '
      'logPath=${config.logPath}',
      isolateTag: 'dl-isolate');

  final SendPort toMain = config.sendPort;
  final ReceivePort port = ReceivePort();
  toMain.send({'type': 'port', 'port': port.sendPort});

  bool canceled = false;
  final List<Map<String, dynamic>> queue =
      List<Map<String, dynamic>>.from(config.items);

  port.listen((msg) {
    if (msg is Map && msg['type'] == 'enqueue') {
      // 追加的任务未经主 isolate 预解析（历史限制）：标记为待解析，
      // worker 内不再访问网络单例，交回主 isolate 处理
      DownloadLogger.log('[worker] enqueue msg ignored (needs resolve on main)',
          isolateTag: 'dl-isolate');
    }
    if (msg is Map && msg['type'] == 'cancel') {
      canceled = true;
      // 取消时直接放行退出闸门（不再等合并）
    }
  });

  int ok = 0;
  int fail = 0;
  DownloadLogger.log('[worker] started, total=${queue.length}',
      isolateTag: 'dl-isolate');
  toMain.send({'type': 'log', 'msg': 'worker started, total=${queue.length}'});

  while (queue.isNotEmpty && !canceled) {
    final item = queue.first;
    final String title = item['title'] ?? '';
    final MediaDownloadPlan? plan = item['plan'] is MediaDownloadPlan
        ? item['plan'] as MediaDownloadPlan
        : null;
    DownloadLogger.log('[worker] begin item cid=${item['cid']} title=$title '
        'plan=${plan != null}',
        isolateTag: 'dl-isolate');
    if (plan == null) {
      // 无预解析计划（不应发生：主 isolate 已保证全部带 plan）：
      // 记为失败并跳过，worker 内绝不能自行查流（网络/单例不可用）
      DownloadLogger.log('[worker] SKIP item without plan cid=${item['cid']}',
          isolateTag: 'dl-isolate');
      fail++;
      toMain.send({'type': 'itemDone', 'ok': false, 'cid': item['cid']});
      queue.removeWhere((e) => e['cid'] == item['cid']);
      continue;
    }
    bool tracksDone = false;
    try {
      // worker 只做纯 Dio 下载（returnAfterTracks：不碰 FFmpegKit——
      // 其原生完成回调会发给本 isolate 的 MethodChannel response，
      // isolate 退出后触发 engine did_send 断言 → 整个 APP 闪退）
      tracksDone = await MediaDownloadService.downloadVideo(
        bvid: item['bvid'],
        cid: item['cid'],
        title: title,
        preferredVideoQa: item['videoQa'],
        preferredDecode: item['decode'],
        silent: true,
        resolved: plan,
        returnAfterTracks: true,
        onProgress: _throttledProgress(toMain, title),
      );
    } catch (e, st) {
      // 理论上 downloadVideo 内部已兜底，这里防止 isolate 因意外异常崩溃
      DownloadLogger.log('[worker] ITEM CRASH cid=${item['cid']}: $e',
          isolateTag: 'dl-isolate');
      DownloadLogger.log('[worker] stack: ${st.toString().split('\n').take(10).join(' | ')}',
          isolateTag: 'dl-isolate');
    }
    if (tracksDone) {
      // 轨道齐了：交回主 isolate 执行 FFmpeg 合并
      DownloadLogger.log('[worker] tracks ready cid=${item['cid']}, merge on main isolate',
          isolateTag: 'dl-isolate');
      toMain.send({
        'type': 'merge',
        'cid': item['cid'],
        'title': title,
        'bvid': item['bvid'],
        'plan': plan,
      });
      queue.removeWhere((e) => e['cid'] == item['cid']);
      continue; // 不计入 ok/fail，等主 isolate mergeDone 消息
    }
    fail++;
    DownloadLogger.log('[worker] item done ok=false remaining=${queue.length}',
        isolateTag: 'dl-isolate');
    queue.removeWhere((e) => e['cid'] == item['cid']);
    toMain.send({
      'type': 'itemDone',
      'ok': false,
      'cid': item['cid'],
    });
    toMain.send({
      'type': 'log',
      'msg': 'item done ok=false remaining=${queue.length}',
    });
  }

  DownloadLogger.log('[worker] loop finished ok=$ok fail=$fail canceled=$canceled',
      isolateTag: 'dl-isolate');

  // worker 是哑化 isolate（无插件端口）：FFmpeg 合并在主 isolate 执行，
  // 所有插件 response 只走主 isolate，did_send 不可能由本 isolate 触发。
  // 直接发送 done 结束即可，无需 exit gate。
  toMain.send({'type': 'done', 'canceled': canceled});
}
