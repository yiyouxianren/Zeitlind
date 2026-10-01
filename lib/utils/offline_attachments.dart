import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pilipala/http/danmaku.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/danmaku/dm.pb.dart';
import 'package:pilipala/utils/download_logger.dart';

/// 离线附属数据（弹幕/分段）落盘与读取。
///
/// 存储位置：app 私有目录 files/offline_danmaku/<视频标题>.dm /
/// <视频标题>.vp.json。文件名与视频文件同名（仅扩展名不同），
/// 播放器据此配对加载。
/// 不放公共 Download 的原因：华为等 ROM 的 FUSE 挂载对旧属主文件读取
/// 会 Permission denied（errno=13），私有目录读写全程无权限障碍。
class OfflineAttachments {
  OfflineAttachments._();

  static String? _cachedDir;

  /// 弹幕/分段文件的存放目录（app 私有 files/offline_danmaku）。
  /// path_provider 需在 UI isolate 调用；结果缓存后各处直接使用。
  static Future<String> danmakuDir() async {
    if (_cachedDir != null) return _cachedDir!;
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory('${base.path}/offline_danmaku');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cachedDir = dir.path;
    return dir.path;
  }

  /// 与 media_download.dart 的 _sanitize 保持一致，
/// 保证同名视频文件与附属文件一一对应。
  static String sanitizeTitle(String name) {
    var result = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
    if (result.isEmpty) result = 'video';
    if (result.length > 120) result = result.substring(0, 120);
    return result;
  }

  static Future<String> danmakuPath(String safeTitle) async =>
      '${await danmakuDir()}/$safeTitle.dm';
  static Future<String> viewPointPath(String safeTitle) async =>
      '${await danmakuDir()}/$safeTitle.vp.json';

  /// 附属文件存在性探测（按视频文件名匹配同名文件）。
  static Future<bool> _fileReadable(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// 是否存在与该视频同名的弹幕文件 <safeTitle>.dm
  static Future<bool> hasDanmakuFile(String safeTitle) async =>
      _fileReadable(await danmakuPath(safeTitle));

  /// 是否存在与该视频同名的分段信息文件 <safeTitle>.vp.json
  static Future<bool> hasViewPointsFile(String safeTitle) async =>
      _fileReadable(await viewPointPath(safeTitle));

  /// 下载弹幕（所有分段，按视频时长循环）+ 分段信息并落盘。
  /// 任何一步失败都不影响主下载流程（失败仅记录日志）。
  static Future<void> downloadAll({
    required String bvid,
    required int cid,
    required int aid,
    required String safeTitle,
    required Duration videoDuration,
  }) async {
    try {
      await _saveDanmaku(cid: cid, safeTitle: safeTitle, videoDuration: videoDuration);
    } catch (e) {
      debugPrint('OfflineAttachments: save danmaku failed: $e');
    }
    try {
      await _saveViewPoints(aid: aid, cid: cid, bvid: bvid, safeTitle: safeTitle);
    } catch (e) {
      debugPrint('OfflineAttachments: save viewPoints failed: $e');
    }
  }

  /// 弹幕按 6 分钟分段拉取，合并成一个 pb 文件。
  static Future<void> _saveDanmaku({
    required int cid,
    required String safeTitle,
    required Duration videoDuration,
  }) async {
    const int segmentLength = 60 * 6 * 1000;
    final int segCount = (videoDuration.inMilliseconds / segmentLength).ceil();
    debugPrint('OfflineAttachments: danmaku segCount=$segCount dur=${videoDuration.inSeconds}s');
    if (segCount <= 0) return;

    final List<List<int>> segments = [];
    for (int i = 1; i <= segCount; i++) {
      try {
        final DmSegMobileReply reply =
            await DanmakaHttp.queryDanmaku(cid: cid, segmentIndex: i);
        segments.add(reply.writeToBuffer());
      } catch (_) {
        segments.add(<int>[]);
      }
    }
    debugPrint('OfflineAttachments: danmaku segments sizes=${segments.map((e) => e.length).toList()}');
    if (segments.every((e) => e.isEmpty)) return;

    // 文件布局：[uint32 段数][每段 uint32 长度 + pb 数据]
    // 手动拼接而非 BytesBuilder：pub 缓存 dart:typed_data 版本会触发
    // AOT/JIT 编译器崩溃（dart:_internal CopyingBytesBuilder toBytes）
    final List<List<int>> chunks = <List<int>>[
      _uint32Bytes(segments.length),
      for (final List<int> seg in segments) ...<List<int>>[
        _uint32Bytes(seg.length),
        seg,
      ],
    ];
    int total = 0;
    for (final List<int> c in chunks) {
      total += c.length;
    }
    final Uint8List bytes = Uint8List(total);
    int offsetW = 0;
    for (final List<int> c in chunks) {
      bytes.setRange(offsetW, offsetW + c.length, c);
      offsetW += c.length;
    }
    final String path = await danmakuPath(safeTitle);
    await File(path).writeAsBytes(bytes);
    debugPrint('OfflineAttachments: danmaku saved ${bytes.length}B -> $path');
  }

  /// 分段信息存 JSON。
  static Future<void> _saveViewPoints({
    required int aid,
    required int cid,
    required String bvid,
    required String safeTitle,
  }) async {
    final List<Map<String, dynamic>> points = await VideoHttp.videoViewPoints(
      aid: aid,
      cid: cid,
      bvid: bvid,
    );
    debugPrint('OfflineAttachments: viewPoints count=${points.length}');
    if (points.isEmpty) return;
    final String path = await viewPointPath(safeTitle);
    final String json = jsonEncode(points);
    await File(path).writeAsString(json);
    debugPrint('OfflineAttachments: viewPoints saved -> $path');
  }

  // ============ 播放侧读取 ============

  /// 读取本地弹幕：返回每段的 DanmakuElem 列表（段索引从 0 开始）。
  /// 文件不存在或损坏返回 null（调用方回退为无弹幕播放）。
  static Future<List<List<DanmakuElem>>?> loadDanmaku(String safeTitle) async {
    try {
      final File file = File(await danmakuPath(safeTitle));
      final bool exists = await file.exists();
      DownloadLogger.log('[loadDanmaku] path=${file.path} exists=$exists');
      if (!exists) return null;
      final List<int> bytes = await file.readAsBytes();
      DownloadLogger.log('[loadDanmaku] read ${bytes.length}B');
      if (bytes.length < 4) return null;

      int offset = 0;
      int count = _readUint32(bytes, 0);
      offset = 4;
      if (count <= 0 || count > 1000) return null;
      final List<List<DanmakuElem>> result = [];
      for (int i = 0; i < count; i++) {
        if (offset + 4 > bytes.length) return null;
        final int len = _readUint32(bytes, offset);
        offset += 4;
        if (len < 0 || offset + len > bytes.length) return null;
        final List<int> seg = bytes.sublist(offset, offset + len);
        offset += len;
        if (seg.isEmpty) {
          result.add(<DanmakuElem>[]);
          continue;
        }
        final DmSegMobileReply reply = DmSegMobileReply.fromBuffer(seg);
        result.add(reply.elems.toList());
      }
      debugPrint('OfflineAttachments: loadDanmaku ok, ${result.length} segments, first=${result.isNotEmpty ? result.first.length : 0} elems');
      DownloadLogger.log('[loadDanmaku] ok segments=${result.length} '
          'first=${result.isNotEmpty ? result.first.length : 0}');
      return result;
    } catch (e) {
      debugPrint('OfflineAttachments: loadDanmaku error: $e');
      DownloadLogger.log('[loadDanmaku] error: $e');
      return null;
    }
  }

  /// 读取本地分段信息。文件不存在返回 null。
  static Future<List<Map<String, dynamic>>?> loadViewPoints(String safeTitle) async {
    try {
      final File file = File(await viewPointPath(safeTitle));
      if (!await file.exists()) return null;
      final String raw = await file.readAsString();
      final dynamic data = jsonDecode(raw);
      if (data is! List) return null;
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static List<int> _uint32Bytes(int value) {
    // 大端
    return <int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  static int _readUint32(List<int> bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
