import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';

Future<void> main() async {
  final lines = File('E:/BILIGAI/android-temp/ws_token.txt').readAsLinesSync();
  final token = lines[0].trim();
  final host = lines[1].trim();
  print('token len=${token.length} host=$host');

  final channel = IOWebSocketChannel.connect('wss://$host:2245/sub',
      connectTimeout: const Duration(seconds: 15));
  await channel.ready;
  print('channel ready (web_socket_channel)');

  final auth = jsonEncode({
    'roomid': 1865936882,
    'uid': 433427845,
    'protover': 3,
    'platform': 'web',
    'type': 2,
    'key': token,
  });
  final payload = utf8.encode(auth);
  final bd = ByteData(16 + payload.length)
    ..setInt32(0, 16 + payload.length, Endian.big)
    ..setInt16(4, 16, Endian.big)
    ..setInt16(6, 1, Endian.big)
    ..setInt32(8, 7, Endian.big)
    ..setInt32(12, 1, Endian.big);
  channel.sink.add([...bd.buffer.asUint8List(), ...payload]);
  print('auth sent');

  final done = Completer<void>();
  final sub = channel.stream.listen((data) {
    if (data is! List<int>) return;
    final b = Uint8List.fromList(data);
    final h = ByteData.sublistView(b);
    final op = h.getUint32(8, Endian.big);
    if (op == 8) {
      print('AUTH REPLY: ${utf8.decode(b.sublist(16))}');
    } else {
      print('op=$op');
    }
    if (!done.isCompleted) done.complete();
  }, onDone: () {
    print('closed');
    if (!done.isCompleted) done.complete();
  });
  try {
    await done.future.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    print('timeout - still open');
  }
  await sub.cancel();
  await channel.sink.close();
}
