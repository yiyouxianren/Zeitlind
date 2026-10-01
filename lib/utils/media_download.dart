import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pilipala/http/constants.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/video/play/url.dart';
import 'package:pilipala/utils/audio_source_utils.dart';
import 'package:pilipala/utils/download.dart';
import 'package:pilipala/utils/download_logger.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:pilipala/utils/id_utils.dart';
import 'package:pilipala/utils/offline_attachments.dart';
import 'package:pilipala/utils/video_utils.dart';

/// 下载类型。
enum MediaDownloadType { audio, video }

/// 预解析好的下载计划：主 isolate 查询 DASH、选轨、读设置后生成，
/// 可直接发给 worker isolate 执行（纯 Dio 下载 + ffmpeg 合并）。
/// 所有字段都是基本类型，保证跨 isolate 传递无依赖。
class MediaDownloadPlan {
  final String videoUrl;
  final String? audioUrl;
  final int? dashDurationMs;

  /// 临时目录绝对路径（主 isolate 用 path_provider 解析后传入，
  /// worker 不再调用任何插件通道，见 downloadVideo 注释）
  final String tmpDirPath;

  const MediaDownloadPlan({
    required this.videoUrl,
    required this.audioUrl,
    required this.dashDurationMs,
    this.tmpDirPath = '',
  });
}

/// 媒体下载：把 B 站视频/音频落盘到公共 Download 目录。
///
/// - 音频：下载 DASH 音轨后用 ffmpeg 转写为 mp3 →
///   `/storage/emulated/0/Download/Zeitlind/music/<标题>.mp3`
/// - 视频：下载视频轨 + 音轨后用 ffmpeg `-c copy` 合并为 MP4 →
///   `/storage/emulated/0/Download/Zeitlind/Video/<标题>.mp4`
class MediaDownloadService {
  MediaDownloadService._();

  static const String _downloadRoot = '/storage/emulated/0/Download/Zeitlind';
  static const String _audioDir = '$_downloadRoot/music';
  static const String _videoDir = '$_downloadRoot/Video';

  static const Map<String, String> _headers = {
    'user-agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_3_1) AppleWebKit/605.1.15 '
            '(KHTML, like Gecko) Version/16.4 Safari/605.1.15',
    'referer': HttpString.baseUrl,
  };

  /// 下载并转写音频为 mp3。
  static Future<bool> downloadAudio({
    required String bvid,
    required int cid,
    required String title,
  }) {
    DownloadLogger.log('[downloadAudio] enter bvid=$bvid cid=$cid title=$title');
    return _guard(() async {
      if (!await _ensureStorageReady()) {
        DownloadLogger.log('[downloadAudio] ABORT: storage not ready');
        return false;
      }
      DownloadLogger.log('[downloadAudio] storage ready');
      final Dash? dash = await _queryDash(bvid: bvid, cid: cid);
      DownloadLogger.log('[downloadAudio] dash=${dash != null ? "ok" : "null"}');
      if (dash == null) {
        SmartDialog.showToast('获取音频流失败');
        return false;
      }

      final int preferred = GStrorage.setting
          .get(SettingBoxKey.defaultAudioQa, defaultValue: 30280);
      final String rawUrl = selectAudioSource(dash, preferred);
      DownloadLogger.log('[downloadAudio] audio picked qa=$preferred url=${rawUrl.length} chars');
      if (rawUrl.isEmpty) {
        SmartDialog.showToast('该视频没有可用的音频流');
        return false;
      }

      await _ensureDir(_audioDir);
      final String safeTitle = _sanitize(title);
      final String outputPath = '$_audioDir/$safeTitle.mp3';
      final Directory tmpDir = await _tempDir();
      // 与视频下载同规则：按 cid 区分，避免残留文件串号
      final String tmpSource = '${tmpDir.path}/a_$cid.m4s';
      DownloadLogger.log('[downloadAudio] tmp=$tmpSource output=$outputPath');

      SmartDialog.showLoading(msg: '下载音频中 0%');
      await _download(rawUrl, tmpSource, (received, total) {
        _progress('下载音频中', received, total);
      });

      SmartDialog.showLoading(msg: '转写 mp3 中');
      final FFmpegSession session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        tmpSource,
        '-vn',
        '-c:a',
        'libmp3lame',
        '-b:a',
        '192k',
        outputPath,
      ]);
      final bool ok = ReturnCode.isSuccess(await session.getReturnCode());
      DownloadLogger.log('[ffmpeg] audio transcode ok=$ok rc=${await session.getReturnCode()}');
      await _cleanup([tmpSource]);
      SmartDialog.dismiss();

      if (!ok) {
        SmartDialog.showToast('音频转写失败：${_tail(await session.getOutput())}');
        return false;
      }
      SmartDialog.showToast('已保存到 Download/Zeitlind/music/$safeTitle.mp3');
      return true;
    });
  }

  /// 下载视频轨 + 音轨并合并为 MP4。
  /// [silent]：静默模式（批量下载时）不弹全局 loading/toast，进度经 [onProgress] 上报
  static Future<bool> downloadVideo({
    required String bvid,
    required int cid,
    required String title,
    int? preferredVideoQa,
    String? preferredDecode,
    bool silent = false,
    void Function(String msg)? onProgress,
    MediaDownloadPlan? resolved,
    bool returnAfterTracks = false,
  }) {
    DownloadLogger.log('[downloadVideo] enter bvid=$bvid cid=$cid silent=$silent '
        'resolved=${resolved != null}');
    return _guard(() async {
      void ui(String msg) {
        if (silent) {
          onProgress?.call(msg);
        } else {
          SmartDialog.showLoading(msg: msg);
        }
      }

      // 前置校验/查询必须在主 isolate 完成：
      // 权限（device_info 走插件通道）与 DASH 查询（VideoHttp 走 Request
      // 单例 + Hive），这两者在 worker isolate 中要么崩溃要么不可用。
      // 调用方（批量服务）会在入队前于主 isolate 调用 [resolvePlan]
      // 预解析好下载计划，worker 通过 [resolved] 直接拿到轨道信息。
      if (resolved == null) {
        final MediaDownloadPlan? plan0 = await resolvePlan(
          bvid: bvid,
          cid: cid,
          preferredVideoQa: preferredVideoQa,
          preferredDecode: preferredDecode,
          toast: silent ? null : (m) => SmartDialog.showToast(m),
        );
        if (plan0 == null) return false;
        resolved = plan0;
      }
      final MediaDownloadPlan plan = resolved!;
      DownloadLogger.log('[downloadVideo] plan: videoHost=${Uri.tryParse(plan.videoUrl)?.host} '
          'audioHost=${plan.audioUrl != null ? Uri.tryParse(plan.audioUrl!)?.host : "none"} '
          'durationMs=${plan.dashDurationMs}');

      await _ensureDir(_videoDir);
      final String safeTitle = _sanitize(title);
      final String outputPath = '$_videoDir/$safeTitle.mp4';
      DownloadLogger.log('[downloadVideo] output=$outputPath');
      // worker 隔离模式（returnAfterTracks=true）绝不调用任何插件通道
      // （path_provider/device_info）：tmp 目录用主 isolate 预解析的路径。
      // 原因：BackgroundIsolateBinaryMessenger.ensureInitialized 在 worker
      // 执行后，ffmpeg_kit 插件的 MethodChannel response 端口被绑到 worker
      // 的 ReceivePort；主 isolate 后续执行 FFmpeg 合并时，原生完成回调的
      // response 仍发往 worker 端口 → engine did_send 断言 → 整个 APP 闪退。
      // worker 完全"哑化"（不注册任何通道）后，所有插件 response 只走主
      // isolate，断言从根源上不可能发生。
      final String tmpPath = returnAfterTracks && plan.tmpDirPath.isNotEmpty
          ? plan.tmpDirPath
          : (await _tempDir()).path;
      // 临时文件按 cid 区分：不同视频共用 cache 目录时绝不互相覆盖
      // （旧实现固定 video_src.m4s，续传时会把别的视频的部分文件当作
      // 本视频的断点，导致 416/进度跳变/合并失败）。
      // ★ worker 模式（returnAfterTracks）绝不在此清理其他 cid 的文件：
      // 上一视频的轨道可能正等主 isolate 合并（跨 isolate 看不到保护集，
      // 误删会导致 ffmpeg No such file）。本轮所有残留由批量服务在
      // 轮次开始时统一清理（cleanupAllTempTracks）。
      if (!returnAfterTracks) {
        _cleanupLegacyTemp(tmpPath,
            currentCid: cid, protectedCids: MediaDownloadService.mergingCids);
      }
      final String tmpVideo = '$tmpPath/v_$cid.m4s';
      final String tmpAudio = '$tmpPath/a_$cid.m4s';

      ui('下载视频中 0%');
      DownloadLogger.log('[downloadVideo] video dl url host=${Uri.tryParse(plan.videoUrl)?.host}');
      await _download(plan.videoUrl, tmpVideo, (received, total) {
        if (silent) {
          onProgress?.call(_progressText('下载视频中', received, total));
        } else {
          _progress('下载视频中', received, total);
        }
      });
      DownloadLogger.log('[downloadVideo] video track downloaded ${await File(tmpVideo).length()}B');

      final bool hasAudio = plan.audioUrl != null;
      if (hasAudio) {
        ui('下载音频中 0%');
        DownloadLogger.log('[downloadVideo] audio dl url host=${Uri.tryParse(plan.audioUrl!)?.host}');
        await _download(plan.audioUrl!, tmpAudio, (received, total) {
          if (silent) {
            onProgress?.call(_progressText('下载音频中', received, total));
          } else {
            _progress('下载音频中', received, total);
          }
        });
        DownloadLogger.log('[downloadVideo] audio track downloaded ${await File(tmpAudio).length()}B');
      }

      ui('合并 MP4 中');
      // 合并阶段：worker isolate 中调用 FFmpegKit 会在原生完成回调时崩溃
      // （FFmpegMethodResultHandler 把 MethodChannel response 发给已退出/
      //  错误绑定的 isolate 端口，engine did_send 断言 → 整个 APP 闪退）。
      // worker 流程经 [returnAfterTracks] 只下载轨道并返回 true；
      // 合并由主 isolate 收到 merge 消息后调 mergeTracks 完成。
      if (returnAfterTracks) {
        DownloadLogger.log('[downloadVideo] tracks done (merge deferred to main isolate)');
        return true;
      }
      return await _mergeAndFinish(
        cid: cid,
        bvid: bvid,
        title: title,
        plan: plan,
        hasAudio: hasAudio,
        tmpVideo: tmpVideo,
        tmpAudio: tmpAudio,
        silent: silent,
        onProgress: onProgress,
      );
    });
  }

  /// 仅合并：轨道已由 worker 下载完成（v_<cid>.m4s / a_<cid>.m4s 在缓存中）。
  /// 必须在主 isolate 调用（FFmpegKit 插件限制，见 downloadVideo 注释）。
  static Future<bool> mergeTracks({
    required int cid,
    required String bvid,
    required String title,
    required MediaDownloadPlan plan,
    required bool hasAudio,
    required String tmpVideo,
    required String tmpAudio,
    bool silent = false,
    void Function(String msg)? onProgress,
  }) {
    DownloadLogger.log('[mergeTracks] enter cid=$cid hasAudio=$hasAudio');
    return _guard(() async {
      final Directory tmpDir = await _tempDir();
      final String v = tmpVideo.isNotEmpty ? tmpVideo : '${tmpDir.path}/v_$cid.m4s';
      final String a = tmpAudio.isNotEmpty ? tmpAudio : '${tmpDir.path}/a_$cid.m4s';
      if (!await File(v).exists()) {
        DownloadLogger.log('[mergeTracks] ABORT: video track missing: $v');
        if (!silent) SmartDialog.showToast('视频轨道缓存丢失，请重新下载');
        return false;
      }
      return await _mergeAndFinish(
        cid: cid,
        bvid: bvid,
        title: title,
        plan: plan,
        hasAudio: hasAudio && await File(a).exists(),
        tmpVideo: v,
        tmpAudio: a,
        silent: silent,
        onProgress: onProgress,
      );
    }, tag: 'mergeTracks');
  }

  /// 合并 + 附属文件 + 清理。合并走 FFmpegKit（主 isolate）。
  static Future<bool> _mergeAndFinish({
    required int cid,
    required String bvid,
    required String title,
    required MediaDownloadPlan plan,
    required bool hasAudio,
    required String tmpVideo,
    required String tmpAudio,
    bool silent = false,
    void Function(String msg)? onProgress,
  }) async {
    void ui(String msg) {
      if (silent) {
        onProgress?.call(msg);
      } else {
        SmartDialog.showLoading(msg: msg);
      }
    }

    void toast(String msg) {
      if (!silent) SmartDialog.showToast(msg);
    }

    await _ensureDir(_videoDir);
    final String safeTitle = _sanitize(title);
    final String outputPath =
        _prepareWritableOutput('$_videoDir/$safeTitle.mp4');
    final List<String> args = hasAudio
        ? <String>[
            '-y',
            '-i',
            tmpVideo,
            '-i',
            tmpAudio,
            '-c',
            'copy',
            '-map',
            '0:v:0',
            '-map',
            '1:a:0',
            '-movflags',
            '+faststart',
            outputPath,
          ]
        : <String>[
            '-y',
            '-i',
            tmpVideo,
            '-c',
            'copy',
            '-movflags',
            '+faststart',
            outputPath,
          ];
    ui('合并 MP4 中');
    DownloadLogger.log('[ffmpeg] merge begin, args=${args.length} '
        'hasAudio=$hasAudio out=$outputPath');
    final FFmpegSession session = await FFmpegKit.executeWithArguments(args);
    final bool ok = ReturnCode.isSuccess(await session.getReturnCode());
    DownloadLogger.log('[ffmpeg] merge done ok=$ok rc=${await session.getReturnCode()}');
    if (!ok) {
      final String? output = await session.getOutput();
      final String tailOut = output == null
          ? 'null'
          : (output.length > 1500 ? output.substring(output.length - 1500) : output);
      DownloadLogger.log('[ffmpeg] merge FAILED, output tail: $tailOut');
    }
    await _cleanup(<String>[tmpVideo, tmpAudio]);
    if (!silent) SmartDialog.dismiss();

    if (!ok) {
      toast('视频合并失败：${_tail(await session.getOutput())}');
      return false;
    }
    toast('已保存到 Download/Zeitlind/Video/$safeTitle.mp4');

    // 同步保存弹幕与分段信息（失败不影响视频下载结果）
    final int aidVal = IdUtils.bv2av(bvid);
    // 视频时长：直接用 DASH 元数据的 duration（毫秒）。
    // 不能用 FFmpegKit 跑 ffprobe 语法（那是 FFprobeKit 的接口，混用必然失败），
    // 旧实现因此永远拿不到时长而静默跳过附属下载。
    final Duration? duration = plan.dashDurationMs != null && plan.dashDurationMs! > 0
        ? Duration(milliseconds: plan.dashDurationMs!)
        : null;
    debugPrint('MediaDownload: dash duration=$duration (ms=${plan.dashDurationMs})');
    DownloadLogger.log('[downloadVideo] output exists=${await File(outputPath).exists()} '
        'size=${await File(outputPath).length()}B');
    DownloadLogger.log('[downloadVideo] attachments duration=$duration');
    if (duration != null) {
      DownloadLogger.log('[downloadVideo] attachments begin');
      await OfflineAttachments.downloadAll(
        bvid: bvid,
        cid: cid,
        aid: aidVal,
        safeTitle: safeTitle,
        videoDuration: duration,
      );
      DownloadLogger.log('[downloadVideo] attachments done');
    } else {
      debugPrint('MediaDownload: skip attachments (no duration)');
    }
    return true;
  }

  /// 主 isolate 预解析：查询 DASH、选轨、读设置，生成可跨 isolate 传递的下载计划。
  /// 失败时返回 null 并给出用户提示。批量下载在入队时调用。
  static Future<MediaDownloadPlan?> resolvePlan({
    required String bvid,
    required int cid,
    int? preferredVideoQa,
    String? preferredDecode,
    void Function(String msg)? toast,
  }) async {
    DownloadLogger.log('[resolvePlan] begin bvid=$bvid cid=$cid '
        'videoQa=$preferredVideoQa decode=$preferredDecode');
    if (!await _ensureStorageReady()) {
      DownloadLogger.log('[resolvePlan] ABORT: storage not ready');
      toast?.call('存储权限未授权，无法下载');
      return null;
    }
    DownloadLogger.log('[resolvePlan] storage ready');
    final Dash? dash = await _queryDash(bvid: bvid, cid: cid);
    DownloadLogger.log('[resolvePlan] dash=${dash != null ? "ok" : "null"}');
    if (dash == null) {
      toast?.call('获取视频流失败');
      return null;
    }
    DownloadLogger.log('[resolvePlan] dash videos=${dash.video?.length} '
        'audio=${dash.audio?.length} duration=${dash.duration}');

    final VideoItem? videoItem = _pickVideoItem(
      dash,
      preferredVideoQa: preferredVideoQa,
      preferredDecode: preferredDecode,
    );
    DownloadLogger.log('[resolvePlan] videoItem=${videoItem != null
        ? "id=${videoItem.id} codecs=${videoItem.codecs} baseUrl=${(videoItem.baseUrl ?? '').length} chars"
        : "null"}');
    if (videoItem == null) {
      toast?.call('该视频没有可用的视频流');
      return null;
    }

    final int preferredAudio = GStrorage.setting
        .get(SettingBoxKey.defaultAudioQa, defaultValue: 30280);
    String? audioRaw;
    try {
      audioRaw = selectAudioSource(dash, preferredAudio);
    } on StateError {
      audioRaw = null; // 无音轨：仅封装视频轨
    }
    DownloadLogger.log('[resolvePlan] audio=${audioRaw != null ? "${audioRaw.length} chars" : "none"}');
    // 主 isolate 预解析临时目录：worker 哑化后不再调用 path_provider
    final Directory tmpDir = await _tempDir();
    final MediaDownloadPlan plan = MediaDownloadPlan(
      videoUrl: VideoUtils.getCdnUrl(videoItem),
      audioUrl: (audioRaw != null && audioRaw.isNotEmpty) ? audioRaw : null,
      dashDurationMs: dash.duration,
      tmpDirPath: tmpDir.path,
    );
    DownloadLogger.log('[resolvePlan] done: videoHost=${Uri.tryParse(plan.videoUrl)?.host} '
        'audioHost=${plan.audioUrl != null ? Uri.tryParse(plan.audioUrl!)?.host : "none"}');
    return plan;
  }

  // ============ 内部工具 ============

  /// 统一异常兜底：保证 loading 关闭并给出可读提示。
  /// [silent]：批量/后台模式下不弹全局 UI（由调用方统一展示），避免弹窗堆积遮屏。
  static Future<bool> _guard(Future<bool> Function() task,
      {bool silent = false, String tag = 'downloadVideo'}) async {
    try {
      return await task();
    } catch (e, st) {
      DownloadLogger.log('[$tag] EXCEPTION: $e');
      DownloadLogger.log('[$tag] stack: ${st.toString().substring(0, st.toString().length > 600 ? 600 : st.toString().length)}');
      if (!silent) SmartDialog.dismiss();
      if (!silent) SmartDialog.showToast('下载失败：$e');
      return false;
    }
  }

  /// 查询 DASH 播放信息（含全部音视频轨）。
  static Future<Dash?> _queryDash({
    required String bvid,
    required int cid,
  }) async {
    DownloadLogger.log('[_queryDash] request begin bvid=$bvid cid=$cid');
    final res = await VideoHttp.videoUrl(bvid: bvid, cid: cid, qn: 80);
    DownloadLogger.log('[_queryDash] response status=${res['status']} '
        'code=${res['code'] ?? '-'} msg=${res['msg'] ?? '-'}');
    if (res['status'] != true) return null;
    final PlayUrlModel data = res['data'] is PlayUrlModel
        ? res['data'] as PlayUrlModel
        : PlayUrlModel();
    return data.dash;
  }

  /// 按质量/编码偏好选视频轨；缺失时回退首个可用轨。
  static VideoItem? _pickVideoItem(
    Dash dash, {
    int? preferredVideoQa,
    String? preferredDecode,
  }) {
    final List<VideoItem> videos = dash.video ?? <VideoItem>[];
    if (videos.isEmpty) return null;

    VideoItem item = videos.first;
    final List<VideoItem> qualityMatched = preferredVideoQa == null
        ? videos
        : videos.where((e) => e.id == preferredVideoQa).toList();
    if (qualityMatched.isNotEmpty) item = qualityMatched.first;

    if (preferredDecode != null && preferredDecode.isNotEmpty) {
      final List<VideoItem> codecMatched = qualityMatched
          .where((e) => (e.codecs ?? '').startsWith(preferredDecode))
          .toList();
      if (codecMatched.isNotEmpty) item = codecMatched.first;
    }
    return item;
  }

  /// 同名检测：该标题的视频/音频是否已存在于下载目录
  /// （离线列表按文件名即标题组织，同名文件 = 已缓存）
  static bool isVideoDownloaded(String title) =>
      File('$_videoDir/${_sanitize(title)}.mp4').existsSync();

  static bool isAudioDownloaded(String title) =>
      File('$_audioDir/${_sanitize(title)}.mp3').existsSync();

  /// 对外暴露的标题清洗（离线缓存页/批量服务与下载侧共用同一规则）
  static String sanitizeTitle(String name) => _sanitize(name);

  /// 视频最终输出路径（批量服务看门狗据此检查 MP4 是否已生成）
  static String videoOutputPath(String title) =>
      '$_videoDir/${_sanitize(title)}.mp4';

  /// 正在（或等待）合并的 cid 集合：worker 下载下一个视频前的临时文件
  /// 迁移清理不得删除这些轨道——它们的主 isolate 合并可能尚未开始。
  /// 由 BatchDownloadService 在入队 merge / 合并完成时维护。
  static final Set<int> mergingCids = <int>{};

  /// 轮次级清理：删除全部轨道临时文件（v_*/a_*.m4s 与旧版固定命名）。
  /// 由批量服务在每轮开始（预解析前、worker 启动前）调用——此时既没有
  /// 进行中的下载也没有待合并的轨道，清理绝对安全。
  static void cleanupAllTempTracks() {
    try {
      final Directory base = _tempDirSync();
      if (!base.existsSync()) return;
      for (final FileSystemEntity e in base.listSync()) {
        final String name = e.uri.pathSegments.last;
        final bool legacy = name == 'video_src.m4s' || name == 'audio_src.m4s';
        final RegExpMatch? m = RegExp(r'^[va]_(\d+)\.m4s$').firstMatch(name);
        if (legacy || m != null) {
          e.deleteSync();
          DownloadLogger.log('[cleanup] round start: removed $name');
        }
      }
    } catch (e) {
      DownloadLogger.log('[cleanup] round cleanup error: $e');
    }
  }

  static Directory _tempDirSync() {
    // path_provider 需要 UI isolate；这里直接按 Android 标准缓存路径走，
    // 与 getTemporaryDirectory 的结果一致（包名固定，不依赖插件通道）
    const String base = '/data/user/0/com.Zeitlind.bill/cache';
    return Directory('$base/media_download');
  }

  /// 下载到本地文件，回调给出进度。
  static Future<void> _download(
    String url,
    String savePath,
    void Function(int received, int total) onProgress,
  ) async {
    // 断点续传 + 网络异常重试：切网/弱网时 Dio 会抛 SocketException，
    // 这里退避重试（已有部分文件时从断点续传），最多 5 次。
    // HTTP 416（Range Not Satisfiable）＝ 本地已有字节 ≥ 文件总长，
    // 即文件已下载完整，直接视为成功（幂等续传场景）。
    const int maxRetries = 5;
    DownloadLogger.log('[_download] begin, host=${Uri.parse(url).host} url=${url.length} chars save=$savePath');
    for (int attempt = 1;; attempt++) {
      int existing = 0;
      try {
        final File f = File(savePath);
        if (await f.exists()) {
          existing = await f.length();
          DownloadLogger.log('[_download] resume from $existing bytes');
        }
        final Options options = Options(
          headers: {
            ..._headers,
            if (existing > 0) 'Range': 'bytes=$existing-',
          },
          // 416 需要进入 catch 分支判断，故显式接受它
          validateStatus: (int? status) =>
              (status != null && status >= 200 && status < 400) || status == 416,
        );
        DownloadLogger.log('[_download] dio.download start, '
            'dioXhrType=Dio(vanilla) existing=$existing');
        final Response rsp = await Dio()
            .download(
              url,
              savePath,
              options: options,
              deleteOnError: false,
              onReceiveProgress: onProgress,
            )
            .timeout(const Duration(minutes: 3));
        if (rsp.statusCode == 416) {
          DownloadLogger.log('[_download] 416 -> file already complete '
              '(local=$existing bytes), treat as success');
          return;
        }
        DownloadLogger.log('[_download] http done, status=${rsp.statusCode} '
            'saved=${await File(savePath).length()} bytes');
        return; // 成功
      } catch (e, st) {
        // Dio 的 download 对 416 会包装为 DioException[bad response]：
        // 这同样是"文件已完整"的信号，直接成功返回
        if (e is DioException && e.response?.statusCode == 416) {
          DownloadLogger.log('[_download] 416 (exception path) -> treat as success, '
              'local=${await File(savePath).length()} bytes');
          return;
        }
        DownloadLogger.log('[_download] attempt=$attempt error=${e.toString()}');
        DownloadLogger.log('[_download] attempt=$attempt errorType=${e.runtimeType}');
        DownloadLogger.log('[_download] stack0=${st.toString().split('\n').take(8).join(' | ')}');
        final bool networkish = e is SocketException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('HttpException') ||
            e.toString().contains('Connection') ||
            e.toString().contains('timeout') ||
            e.toString().contains('Timeout');
        if (attempt >= maxRetries || !networkish) rethrow;
        // 退避：2s、4s、8s、16s（给切网/恢复留时间）
        final int waitSec = 1 << attempt; // 2,4,8,16
        DownloadLogger.log('[_download] retry in ${waitSec}s');
        await Future<void>.delayed(Duration(seconds: waitSec));
      }
    }
  }

  /// 输出文件冲突预处理：
  /// 公共 Download 经 FUSE 挂载时，由其它 app（或本 app 以媒体卷路径）创建
  /// 的同名文件属于 media_rw，本进程无写权限 → ffmpeg 直接 Permission denied。
  /// 处理：不可写则删除残留（cache 目录归我们所有，可删）；删除失败或
  /// 文件来自未知来源时退回带序号的文件名（不破坏用户已有文件）。
  static String _prepareWritableOutput(String path) {
    try {
      final File f = File(path);
      if (!f.existsSync()) return path;
      try {
        // 以追加模式打开验证写权限（不动文件内容）
        final RandomAccessFile raf = f.openSync(mode: FileMode.append);
        raf.closeSync();
        return path;
      } catch (_) {
        try {
          f.deleteSync();
          DownloadLogger.log('[output] deleted unwritable leftover: $path');
          return path;
        } catch (e) {
          final String ext = path.substring(path.lastIndexOf('.'));
          final String base = path.substring(0, path.length - ext.length);
          final String alt = '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
          DownloadLogger.log('[output] not writable ($e), fallback: $alt');
          return alt;
        }
      }
    } catch (e) {
      DownloadLogger.log('[output] prepare failed: $e');
      return path;
    }
  }

  static void _progress(String label, int received, int total) {    if (total <= 0) return;
    final int percent = (received * 100 / total).clamp(0, 100).toInt();
    SmartDialog.showLoading(msg: '$label $percent%');
  }

  /// 静默模式进度文本（不弹 UI，由调用方展示）
  static String _progressText(String label, int received, int total) {
    if (total <= 0) return label;
    final int percent = (received * 100 / total).clamp(0, 100).toInt();
    return '$label $percent%';
  }

  /// 校验/申请存储权限。Android 10+ 写公共 Download 无需额外授权。
  static Future<bool> _ensureStorageReady() async {
    if (!Platform.isAndroid) return true;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    DownloadLogger.log('[_ensureStorageReady] sdkInt=${androidInfo.version.sdkInt}');
    // 存储权限所有 Android 版本都显式申请：华为等厂商 ROM 的 FUSE 实现
    // 缺旧存储权限时对公共 Download 读写会被拒（标准 AOSP 10+ 虽无需，
    // 但已授予时 request() 立即返回，不会重复弹窗）。
    // Android 13+ 上 Permission.storage 映射到 READ_MEDIA_*，同样适用。
    final bool ok = await DownloadUtils.requestStoragePer();
    DownloadLogger.log('[_ensureStorageReady] storage perm=$ok');
    return ok;
  }

  static Future<void> _ensureDir(String path) async {
    final Directory dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  static Future<Directory> _tempDir() async {
    final Directory base = await getTemporaryDirectory();
    final Directory dir = Directory('${base.path}/media_download');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> _cleanup(List<String> paths) async {
    for (final String p in paths) {
      try {
        final File f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 清理失败不影响主流程
      }
    }
  }

  /// 迁移清理：删掉旧版固定命名（video_src/audio_src.m4s）与其它 cid 的
  /// 临时文件，避免旧残留与新 cid 命名规则继续串号。清理失败静默忽略。
  /// [protectedCids]：正在等待/执行合并的轨道所属 cid，绝不删除。
  static void _cleanupLegacyTemp(String dirPath,
      {required int currentCid, Set<int>? protectedCids}) {
    try {
      final Directory dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      final List<FileSystemEntity> entries = dir.listSync();
      for (final FileSystemEntity e in entries) {
        final String name = e.uri.pathSegments.last;
        final RegExp cidRe = RegExp(r'^[va]_(\d+)\.m4s$');
        final RegExpMatch? m = cidRe.firstMatch(name);
        if (name == 'video_src.m4s' || name == 'audio_src.m4s') {
          e.deleteSync();
          DownloadLogger.log('[cleanup] removed legacy temp: $name');
        } else if (m != null) {
          final int fileCid = int.tryParse(m.group(1)!) ?? -1;
          if (fileCid == currentCid || (protectedCids?.contains(fileCid) ?? false)) {
            continue; // 本视频或合并保护集中的轨道：保留
          }
          e.deleteSync();
          DownloadLogger.log('[cleanup] removed stale temp: $name');
        }
      }
    } catch (e) {
      DownloadLogger.log('[cleanup] legacy temp cleanup error: $e');
    }
  }

  /// 清理文件名中的非法字符，避免创建失败。
  static String _sanitize(String name) {
    var result = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
    if (result.isEmpty) result = 'video';
    if (result.length > 120) result = result.substring(0, 120);
    return result;
  }

  /// 取日志末尾若干行，用于失败提示。
  static String _tail(String? log) {
    if (log == null || log.isEmpty) return '未知错误';
    final List<String> lines =
        log.split('\n').where((e) => e.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '未知错误';
    final String last = lines.last;
    return last.length > 120 ? last.substring(last.length - 120) : last;
  }

  /// 便捷入口：按类型下载。
  static Future<bool> download({
    required MediaDownloadType type,
    required String bvid,
    required int cid,
    required String title,
    int? videoQa,
    String? decode,
  }) {
    if (type == MediaDownloadType.audio) {
      return downloadAudio(bvid: bvid, cid: cid, title: title);
    }
    return downloadVideo(
      bvid: bvid,
      cid: cid,
      title: title,
      preferredVideoQa: videoQa,
      preferredDecode: decode,
    );
  }
}
