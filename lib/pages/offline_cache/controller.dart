import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pilipala/utils/offline_attachments.dart';

/// 单个离线视频条目
class OfflineVideoItem {
  OfflineVideoItem({
    required this.path,
    required this.title,
    required this.sizeBytes,
    required this.modified,
  });

  final String path;
  final String title;
  final int sizeBytes;
  final DateTime modified;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// 离线缓存页控制器：扫描 Download/Zeitlind/Video 与 music 目录。
class OfflineCacheController extends GetxController {
  static const String downloadRoot = '/storage/emulated/0/Download/Zeitlind';
  static const String videoDir = '$downloadRoot/Video';
  static const String musicDir = '$downloadRoot/music';
  // 弹幕/分段文件已迁移至 app 私有目录（OfflineAttachments.danmakuDir），
  // 公共 danmaku/ 目录仅作为旧数据迁移源。

  final ScrollController scrollController = ScrollController();
  RxList<OfflineVideoItem> videoList = <OfflineVideoItem>[].obs;
  RxList<OfflineVideoItem> musicList = <OfflineVideoItem>[].obs;
  RxBool loading = false.obs;
  RxString errorMsg = ''.obs;

  /// 批量删除多选模式：选中项为完整文件路径
  RxBool batchMode = false.obs;
  RxSet<String> selectedPaths = <String>{}.obs;

  Future<void> refreshList() async {
    loading.value = true;
    errorMsg.value = '';
    try {
      videoList.value = await _scan(videoDir);
      musicList.value = await _scan(musicDir);
    } catch (e) {
      errorMsg.value = '读取下载目录失败：$e';
    } finally {
      loading.value = false;
    }
  }

  Future<List<OfflineVideoItem>> _scan(String dirPath) async {
    final Directory dir = Directory(dirPath);
    if (!await dir.exists()) {
      return const <OfflineVideoItem>[];
    }
    final List<OfflineVideoItem> items = [];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final String name = entity.path.split('/').last;
      final bool isMedia =
          name.toLowerCase().endsWith('.mp4') || name.toLowerCase().endsWith('.m4a') || name.toLowerCase().endsWith('.mp3') || name.toLowerCase().endsWith('.mkv') || name.toLowerCase().endsWith('.flac');
      if (!isMedia) continue;
      final FileStat stat = await entity.stat();
      items.add(OfflineVideoItem(
        path: entity.path,
        // 文件名即视频标题（下载时已按标题保存）
        title: _stripExt(name),
        sizeBytes: stat.size,
        modified: stat.modified,
      ));
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  /// 导入外部文件：用户从系统文件选择器挑视频/音频（可多选），
  /// 复制进 Zeitlind 目录后即可像正常缓存一样出现在列表并播放。
  /// 弹幕配对：若所选文件同目录存在 <同名>.dm / <同名>.vp.json（旧版本
  /// app 或手动下载的附属文件），会一并复制到 danmaku/ 目录——否则播放
  /// 时按文件名找不到弹幕。也支持直接选 .dm 弹幕文件导入。
  Future<void> importFromFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>[
        'mp4', 'mkv', 'm4a', 'mp3', 'flac', 'dm', 'json',
      ],
      allowMultiple: true,
      allowCompression: false,
    );
    if (result == null || result.files.isEmpty) return;
    int imported = 0;
    int skipped = 0;
    List<String> failed = [];
    try {
      loading.value = true;
      SmartDialog.showLoading(msg: '导入中...');
      for (final PlatformFile pick in result.files) {
        final String sourcePath = pick.path ?? '';
        if (sourcePath.isEmpty) continue;
        final String name = sourcePath.split('/').last;
        final int dot = name.lastIndexOf('.');
        final String ext =
            dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
        final String baseName = dot > 0 ? name.substring(0, dot) : name;

        if (ext == 'dm' || name.endsWith('.vp.json')) {
          // 直接导入弹幕/分段文件
          final bool ok = await _importAttachment(sourcePath, name);
          ok ? imported++ : skipped++;
          continue;
        }

        final bool isAudio = ext == 'mp3' || ext == 'flac' || ext == 'm4a';
        final String destDir = isAudio ? musicDir : videoDir;
        final String destPath = '$destDir/$name';
        final Directory dir = Directory(destDir);
        if (!await dir.exists()) await dir.create(recursive: true);
        if (await File(destPath).exists()) {
          skipped++;
          continue;
        }
        try {
          await File(sourcePath).copy(destPath);
          imported++;
          // 带走同目录同名附属文件（旧版本缓存的弹幕/分段）
          await _tryCopySiblingAttachments(sourcePath, baseName);
        } catch (e) {
          failed.add(name);
        }
      }
      SmartDialog.dismiss();
      final String msg = '导入 $imported 个文件'
          '${skipped > 0 ? '，跳过已存在 $skipped 个' : ''}'
          '${failed.isNotEmpty ? '，失败 ${failed.length} 个' : ''}';
      SmartDialog.showToast(msg);
      await refreshList();
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('导入失败：$e');
    } finally {
      loading.value = false;
    }
  }

  /// 复制媒体文件同目录下的 <同名>.dm / <同名>.vp.json 到私有弹幕目录。
  /// 找不到或已存在则静默跳过。
  Future<void> _tryCopySiblingAttachments(
      String sourcePath, String baseName) async {
    try {
      final String sourceDir = sourcePath.substring(0, sourcePath.lastIndexOf('/'));
      final String danDir = await OfflineAttachments.danmakuDir();
      for (final String suffix in <String>['$baseName.dm', '$baseName.vp.json']) {
        final File src = File('$sourceDir/$suffix');
        if (!await src.exists()) continue;
        final File dst = File('$danDir/$suffix');
        if (await dst.exists()) continue;
        await src.copy(dst.path);
      }
    } catch (_) {
      // 附属文件带不过来不影响视频导入本身
    }
  }

  /// 导入弹幕(.dm)/分段(.vp.json)文件到私有弹幕目录。
  Future<bool> _importAttachment(String sourcePath, String name) async {
    try {
      final String danDir = await OfflineAttachments.danmakuDir();
      final File dst = File('$danDir/$name');
      if (await dst.exists()) return false;
      await File(sourcePath).copy(dst.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _stripExt(String name) {
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  void toggleSelect(String path) {
    if (!selectedPaths.remove(path)) {
      selectedPaths.add(path);
    }
  }

  /// 删除选中项：
  /// - 视频项：删除 mp4 + danmaku/<同名>.dm + danmaku/<同名>.vp.json
  /// - 音频项：仅删除音频文件
  Future<void> deleteSelected() async {
    if (selectedPaths.isEmpty) return;
    final List<String> targets = selectedPaths.toList();
    int deleted = 0;
    int freedBytes = 0;
    try {
      for (final path in targets) {
        final File file = File(path);
        if (await file.exists()) {
          freedBytes += await file.length();
          await file.delete();
          deleted++;
          // 视频项同步清理弹幕/分段（同名配对，私有目录）
          if (path.startsWith(videoDir)) {
            final String title = _stripExt(path.split('/').last);
            final String danDir = await OfflineAttachments.danmakuDir();
            final File dm = File('$danDir/$title.dm');
            if (await dm.exists()) await dm.delete();
            final File vp = File('$danDir/$title.vp.json');
            if (await vp.exists()) await vp.delete();
          }
        }
      }
      SmartDialog.showToast('已删除 $deleted 项'
          '${freedBytes >= 1024 * 1024 ? '，释放 ${(freedBytes / 1024 / 1024).toStringAsFixed(1)} MB' : ''}');
    } catch (e) {
      SmartDialog.showToast('删除失败：$e');
    } finally {
      selectedPaths.clear();
      batchMode.value = false;
      await refreshList();
    }
  }

  @override
  void onInit() {
    super.onInit();
    refreshList();
  }
}
