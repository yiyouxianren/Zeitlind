import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// 直播弹幕连接协议（移植自 PiliPlus lib/tcp/live.dart）：
/// - package: ProtocolHeader(16B) + payload（压缩帧的 payload 解压后为内嵌的标准帧）
/// - operationCode: 2=心跳 3=心跳回复 5=消息(JSON) 7=认证 8=认证回复
enum SocketStatus {
  connected,
  connecting,
  failed,
  closed,
}

class _PackageHeaderRes {
  final int totalSize;
  final int headerSize;
  final int protocolVer;
  final int operationCode;
  final int seq;

  const _PackageHeaderRes({
    required this.totalSize,
    required this.headerSize,
    required this.protocolVer,
    required this.operationCode,
    required this.seq,
  });

  static _PackageHeaderRes? fromBytesData(Uint8List data) {
    if (data.length < 16) return null;
    final byteData = ByteData.sublistView(data);
    return _PackageHeaderRes(
      totalSize: byteData.getUint32(0, Endian.big),
      headerSize: byteData.getUint16(4, Endian.big),
      protocolVer: byteData.getUint16(6, Endian.big),
      operationCode: byteData.getUint32(8, Endian.big),
      seq: byteData.getUint32(12, Endian.big),
    );
  }
}

/// 直播弹幕连接，对齐 PiliPlus 的 LiveMessageStream：
/// 逐个 server 建立连接，收到认证回复(op=8)后开启 30s 心跳，
/// 解压后把每个内嵌标准帧的 JSON 正文交给监听器。
class PlSocket {
  PlSocket({
    required this.url,
    this.heartTime = 30,
    this.onReadyCb,
    this.onCloseCb,
    this.onErrorCb,
    this.onMessageCb,
    this.onStatusCb,
    this.onAuthRejectedCb,
    this.extraHeaders,
    List<String>? urls,
  }) : servers = _uniqueUrls(url, urls);

  final String url;
  final List<String> servers;
  final int heartTime;
  final Function? onReadyCb;
  final Function? onCloseCb;
  final Function? onErrorCb;
  final Function? onMessageCb;
  final Function(SocketStatus)? onStatusCb;
  final Map<String, String>? extraHeaders;

  /// 认证阶段被服务器断开时回调（用于上层降级 uid 重连）
  final void Function()? onAuthRejectedCb;

  static final ZLibDecoder _zlib = ZLibDecoder();

  bool _active = true;
  int _heartBeatCount = 1;
  WebSocket? _ws;
  StreamSubscription? _socketSubscription;
  Timer? _timer;

  SocketStatus status = SocketStatus.closed;

  void _setStatus(SocketStatus value) {
    status = value;
    onStatusCb?.call(value);
  }

  Future<void> connect() async {
    _authenticated = false;
    _setStatus(SocketStatus.connecting);
    debugPrint('PlSocket.connect servers=$servers');
    try {
      for (final server in servers) {
        try {
          debugPrint('PlSocket connecting $server');
          final ws = await WebSocket.connect(
            server,
            headers: {
              'Origin': 'https://live.bilibili.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              ...?extraHeaders,
            },
          );
          debugPrint('PlSocket connected $server readyState=${ws.readyState}');
          if (!_active) {
            _closeChannel(ws);
            return;
          }
          _ws = ws;
          break;
        } catch (e) {
          debugPrint('PlSocket connect failed $server: $e');
        }
      }
      if (_ws == null) {
        throw Exception('all servers connect failed');
      }
      _socketSubscription = _ws!.listen(
        onData,
        onDone: _onClosed,
        onError: (e) {
          debugPrint('PlSocket stream error: $e');
          _onClosed();
        },
        cancelOnError: false,
      );
      _setStatus(SocketStatus.connecting);
      onReadyCb?.call();
      sendAuth();
    } catch (e) {
      debugPrint('PlSocket.connect error: $e');
      _onError('弹幕地址链接失败: $e');
    }
  }

  // 认证包；uid/roomid/token 由上层在连接前赋值
  int uid = 0;
  int roomid = 0;
  String? key;

  void sendAuth() {
    if (_ws == null) {
      debugPrint('PlSocket.sendAuth skipped: no socket');
      return;
    }
    if (key == null) {
      debugPrint('PlSocket.sendAuth skipped: no key');
      return;
    }
    final json = utf8.encode(jsonEncode({
      'roomid': roomid,
      'uid': uid,
      'protover': 3,
      'platform': 'web',
      'type': 2,
      'key': key,
    }));
    final header = _header(7, 1, 1, contentSize: json.length);
    final payload = Uint8List.fromList([...header, ...json]);
    debugPrint(
        'PlSocket.sendAuth roomid=$roomid uid=$uid keyLen=${key!.length} payloadLen=${payload.length}');
    _ws!.add(payload);
  }

  List<int> _header(int op, int seq, int ver, {int contentSize = 0}) {
    final bytes = ByteData(16)
      // totalSize = 头(16) + 正文长度；认证包漏掉正文长度会被服务器静默断开
      ..setInt32(0, 16 + contentSize, Endian.big)
      ..setInt16(4, 16, Endian.big)
      ..setInt16(6, ver, Endian.big)
      ..setInt32(8, op, Endian.big)
      ..setInt32(12, seq, Endian.big);
    return bytes.buffer.asUint8List();
  }

  void _heartBeat() {
    _setStatus(SocketStatus.connected);
    _timer ??= Timer.periodic(Duration(seconds: heartTime), (timer) {
      if (!_active) {
        timer.cancel();
        _onClosed();
        return;
      }
      try {
        _ws?.add(_header(2, _heartBeatCount++, 1));
      } catch (_) {
        timer.cancel();
      }
    });
  }

  /// 连接后是否成功通过认证（收到 op=8 回复）
  bool get authenticated => _authenticated;
  bool _authenticated = false;

  void onData(dynamic data) {
    if (data is! List<int>) {
      debugPrint('PlSocket onData non-binary: ${data.runtimeType}');
      return;
    }
    final header = _PackageHeaderRes.fromBytesData(data as Uint8List);
    if (header == null) {
      debugPrint('PlSocket onData unparseable frame len=${(data).length}');
      return;
    }
    // 心跳回复不用处理
    if (header.operationCode == 3) return;
    // 认证回复，开启心跳
    if (header.operationCode == 8) {
      debugPrint('PlSocket auth reply ver=${header.protocolVer}');
      _authenticated = true;
      _heartBeat();
    }
    final List<int> decompressedData;
    try {
      switch (header.protocolVer) {
        case 0:
        case 1:
          _processingData(data);
          return;
        case 2:
          decompressedData = _zlib.convert(Uint8List.sublistView(data, 0x10));
          break;
        case 3:
          decompressedData = brotli.decode(Uint8List.sublistView(data, 0x10));
          break;
        default:
          debugPrint('PlSocket unknown protocolVer=${header.protocolVer}');
          return;
      }
      _processingData(
        decompressedData is Uint8List
            ? decompressedData
            : Uint8List.fromList(decompressedData),
      );
    } catch (e) {
      debugPrint('PlSocket decode failed ver=${header.protocolVer}: $e');
    }
  }

  void _processingData(Uint8List data) {
    try {
      final subHeader = _PackageHeaderRes.fromBytesData(data);
      if (subHeader != null) {
        if (subHeader.operationCode == 5) {
          onMessageCb?.call(utf8.decode(
            Uint8List.sublistView(
                data, subHeader.headerSize, subHeader.totalSize),
          ));
        }
        if (subHeader.totalSize < data.length) {
          _processingData(Uint8List.sublistView(data, subHeader.totalSize));
        }
      }
    } catch (_) {}
  }

  void _onClosed() {
    debugPrint(
        'PlSocket closed authenticated=$_authenticated uid=$uid roomid=$roomid');
    if (status != SocketStatus.failed) {
      _setStatus(SocketStatus.closed);
    }
    _closeChannel(_ws);
    _ws = null;
    onCloseCb?.call();
    // 服务器在认证阶段直接断开（token 与 uid 不匹配时静默 close）
    if (!_authenticated) {
      onAuthRejectedCb?.call();
    }
  }

  void _onError(String msg) {
    _setStatus(SocketStatus.failed);
    onErrorCb?.call(msg);
  }

  void _closeChannel(WebSocket? ws) {
    try {
      ws?.close();
    } catch (_) {}
  }

  Future<void> onClose({bool notify = true}) async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    final ws = _ws;
    _ws = null;
    _closeChannel(ws);
    _setStatus(SocketStatus.closed);
    if (notify) onCloseCb?.call();
  }

  static List<String> _uniqueUrls(String first, List<String>? candidates) {
    final values = <String>[first, ...?candidates]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    return values.isEmpty ? [first] : values;
  }
}
