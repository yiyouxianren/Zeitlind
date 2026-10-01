import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/models/live/message.dart';
import 'package:pilipala/utils/live.dart';

List<int> packet(String body, {int operation = 5, int version = 0}) {
  final data = utf8.encode(body);
  final bytes = ByteData(16);
  bytes.setInt32(0, 16 + data.length);
  bytes.setInt16(4, 16);
  bytes.setInt16(6, version);
  bytes.setInt32(8, operation);
  bytes.setInt32(12, 1);
  final result = bytes.buffer.asUint8List().toList()..addAll(data);
  return result;
}

void main() {
  test('decodes a danmu message', () {
    final result = LiveUtils.decodeMessage(packet(jsonEncode({
      'cmd': 'DANMU_MSG',
      'info': [
        [0, 1, 0, 16711680],
        'hello',
        [123],
      ],
    })));

    expect(result, hasLength(1));
    expect(result!.single.message, 'hello');
    expect(result.single.uid, 123);
  });

  test('reads the current live user payload layout', () {
    final result = LiveUtils.decodeMessage(packet(jsonEncode({
      'cmd': 'DANMU_MSG',
      'info': [
        [0, 1, 0, 65280, 0, 0, 0, 0, 0, 0, 998],
        'new layout',
        [321],
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        {
          'user': {
            'uid': 321,
            'base': {'name': '主播粉丝', 'face': 'https://example.com/face'}
          },
          'extra': jsonEncode({'emots': {}}),
        },
      ],
    })));

    expect(result, hasLength(1));
    expect(result!.single.userName, '主播粉丝');
    expect(result.single.uid, 321);
    expect(result.single.dmid, 998);
  });

  test('parses super chat and interaction messages', () {
    final superChat = LiveUtils.decodeMessage(packet(jsonEncode({
      'cmd': 'SUPER_CHAT_MESSAGE',
      'data': {
        'user_info': {'uname': '支持者', 'face': 'https://example.com/face'},
        'message': '加油',
        'price': 30,
        'start_time': 100,
        'end_time': 200,
      },
    })));
    expect(superChat, hasLength(1));
    expect(superChat!.single.type, LiveMessageType.superChat);
    expect(superChat.single.userName, '支持者');

    final interaction = LiveUtils.decodeMessage(packet(jsonEncode({
      'cmd': 'INTERACT_WORD',
      'data': {'uid': 456, 'uname': '新观众', 'msg_type': 1},
    })));
    expect(interaction, hasLength(1));
    expect(interaction!.single.type, LiveMessageType.join);
    expect(interaction.single.uid, 456);
  });

  test('keeps valid messages when another packet is malformed', () {
    final data = <int>[]
      ..addAll(packet('{bad json'))
      ..addAll(packet(jsonEncode({
        'cmd': 'DANMU_MSG',
        'info': [
          [0, 1, 0, 0],
          'valid',
          [456],
        ],
      })));

    final result = LiveUtils.decodeMessage(data);
    expect(result, hasLength(1));
    expect(result!.single.message, 'valid');
  });
}
