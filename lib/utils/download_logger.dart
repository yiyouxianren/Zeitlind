import 'dart:io';

import 'package:flutter/foundation.dart';

/// 下载全链路调试日志：写入 Download/Zeitlind/downloadlog_DD_HH_MM_SS.txt
/// 每次冷启动创建新文件（按启动时刻命名），主 isolate 与下载 isolate 共用追加。
class DownloadLogger {
  DownloadLogger._();

  static const String rootDir = '/storage/emulated/0/Download/Zeitlind';

  static File? _file;
  static final StringBuffer _buffer = StringBuffer();

  /// 保证 Zeitlind 根目录存在（华为部分 ROM Download 目录可能未创建）。
  static void _ensureRoot() {
    try {
      final Directory d = Directory(rootDir);
      if (!d.existsSync()) d.createSync(recursive: true);
    } catch (_) {}
  }

  /// 当前日志文件路径（每次冷启动首次访问时确定）。
  static String get filePath {
    if (_file == null) {
      _ensureRoot();
      final now = DateTime.now();
      final dd = now.day.toString().padLeft(2, '0');
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final ss = now.second.toString().padLeft(2, '0');
      _file = File('$rootDir/downloadlog_$dd-$hh-$mm-$ss.txt');
    }
    return _file!.path;
  }

  /// 供下载 isolate 传入的日志文件路径（isolate 内静态变量不共享，
  /// 显式传入后 worker 写同一个文件）。
  static void usePath(String path) {
    _file ??= File(path);
  }

  /// 在 isolate 中使用：每次调用直接同步落盘（isolate 间无法共享静态变量）
  static void log(String msg, {String? isolateTag}) {
    final line =
        '[${DateTime.now().toIso8601String()}]'
        '${isolateTag != null ? '[$isolateTag]' : ''} $msg';
    debugPrint(line);
    try {
      // 直接同步追加（文件较小，性能无碍）
      final f = _file ?? File(filePath);
      f.writeAsStringSync('$line\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
    _buffer.writeln(line);
  }

  /// 读取日志全文（调试用）
  static String readAll() {
    try {
      final f = _file ?? File(filePath);
      if (f.existsSync()) return f.readAsStringSync();
    } catch (_) {}
    return '';
  }
}
