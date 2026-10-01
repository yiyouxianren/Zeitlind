import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main() async {
  final lines = File('E:/BILIGAI/android-temp/ws_token.txt').readAsLinesSync();
  final token = lines[0].trim();
  final host = lines[1].trim();
  print('token len=${token.length} host=$host');

  final ws = await WebSocket.connect('wss://$host:2245/sub', headers: {
    'Origin': 'https://live.bilibili.com',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  });
  print('connected');
  final auth = jsonEncode({
    'roomid': 1865936882,
    'uid': 433427845,
    'protover': 3,
    'platform': 'web',
    'type': 2,
    'key': token,
  });
  final jsonBytes = utf8.encode(auth);
  // 正确写法：16B 头 + json（与 PlSocket 一致）
  final header = ByteData(16)
    ..setInt32(0, 16 + jsonBytes.length, Endian.big)
    ..setInt16(4, 16, Endian.big)
    ..setInt16(6, 1, Endian.big)
    ..setInt32(8, 7, Endian.big)
    ..setInt32(12, 1, Endian.big);
  final payload = Uint8List.fromList([...header.buffer.asUint8List(), ...jsonBytes]);
  print('payload=${payload.length}B (期望 ${16 + jsonBytes.length})');
  ws.add(payload);

  final done = Completer<void>();
  final sub = ws.listen((data) {
    if (data is! List<int>) return;
    final b = Uint8List.fromList(data);
    final h = ByteData.sublistView(b);
    final op = h.getUint32(8, Endian.big);
    if (op == 8) {
      print('AUTH OK: ${utf8.decode(b.sublist(16))}');
    } else {
      print('op=$op');
    }
    if (!done.isCompleted) done.complete();
  }, onDone: () {
    print('closed by server');
    if (!done.isCompleted) done.complete();
  });
  try {
    await done.future.timeout(const Duration(seconds: 8));
  } on TimeoutException {
    print('timeout - still open (good sign)');
  }
  await sub.cancel();
  await ws.close();
}
