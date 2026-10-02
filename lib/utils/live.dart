import 'dart:convert';

import 'package:pilipala/models/live/message.dart';

/// 直播弹幕 JSON 消息解析（对齐 PiliPlus 的 _danmakuListener）
class LiveUtils {
  static LiveMessageModel? parseMessage(String jsonMessage) {
    try {
      final obj = jsonDecode(jsonMessage);
      if (obj is! Map) return null;
      switch (obj['cmd']) {
        case 'DANMU_MSG':
          final info = obj['info'];
          if (info is! List || info.length < 2) return null;
          final first = info[0];
          if (first is! List || first.length < 16) return null;
          final content = first[15];
          if (content is! Map) return null;
          final user = content['user'];
          if (user is! Map) return null;
          final uid = user['uid'];
          final userEmote = first.length > 13 && first[13] is Map
              ? Map<String, dynamic>.from(first[13] as Map)
              : null;
          final msg = info[1];
          if (msg is! String) return null;
          Map<String, dynamic>? extra;
          try {
            final decoded = jsonDecode(content['extra'] ?? '{}');
            if (decoded is Map<String, dynamic>) extra = decoded;
          } catch (_) {}
          extra ??= const {};
          final base = user['base'] is Map ? user['base'] as Map : const {};
          final name = (base['name'] ?? user['uname'] ?? '用户').toString();
          final colorValue = _asInt(extra['color']) ??
              (first.length > 3 ? _asInt(first[3]) : null) ??
              0;
          // 粉丝牌：info[3] = [level, name, 创建主播名, ...]
          // （name 为空串表示该用户没有粉丝牌）
          final medal = info.length > 3 && info[3] is List ? info[3] as List : null;
          final medalLevel = medal != null && medal.isNotEmpty
              ? _asInt(medal[0])
              : null;
          final String? medalName = medal != null &&
                  medal.length > 1 &&
                  medal[1] is String &&
                  (medal[1] as String).isNotEmpty
              ? medal[1] as String
              : null;
          return LiveMessageModel(
            type: LiveMessageType.chat,
            userName: name,
            message: msg,
            color: colorValue == 0
                ? LiveMessageColor.white
                : LiveMessageColor.numberToColor(colorValue),
            face: base['face']?.toString(),
            uid: _asInt(uid),
            emots: _readEmotes(extra['emots']),
            emote: userEmote,
            dmid: _asInt(extra['id_str']) ??
                (first.length > 10 ? _asInt(first[10]) : null),
            medalName: medalName != null && medalLevel != null ? medalName : null,
            medalLevel: medalName != null && medalLevel != null ? medalLevel : null,
          );
        case 'SUPER_CHAT_MESSAGE':
          final data = obj['data'];
          if (data is! Map) return null;
          final userInfo =
              data['user_info'] is Map ? data['user_info'] as Map : const {};
          DateTime? time(dynamic value) {
            final seconds = _asInt(value);
            return seconds == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
          }

          return LiveMessageModel(
            type: LiveMessageType.superChat,
            userName: (userInfo['uname'] ?? '用户').toString(),
            message: data['message']?.toString() ?? '',
            color: LiveMessageColor.white,
            data: {
              'backgroundBottomColor':
                  data['background_bottom_color']?.toString() ?? '',
              'backgroundColor': data['background_color']?.toString() ?? '',
              'endTime': time(data['end_time']),
              'startTime': time(data['start_time']),
              'face': userInfo['face']?.toString() ?? '',
              'message': data['message']?.toString() ?? '',
              'price': data['price']?.toString() ?? '',
              'userName': userInfo['uname']?.toString() ?? '用户',
            },
          );
        case 'INTERACT_WORD':
        case 'ENTRY_EFFECT':
          final data = obj['data'];
          if (data is! Map) return null;
          final msgType = _asInt(data['msg_type']);
          final isFollow =
              obj['cmd'] == 'INTERACT_WORD' && msgType != null && msgType != 1;
          return LiveMessageModel(
            type: isFollow ? LiveMessageType.follow : LiveMessageType.join,
            userName: (data['uname'] ?? data['username'] ?? '用户').toString(),
            message: isFollow ? '关注了主播' : '进入直播间',
            color: LiveMessageColor.white,
            uid: _asInt(data['uid'] ?? data['uid_str']),
          );
        case 'WATCHED_CHANGE':
          final data = obj['data'];
          return LiveMessageModel(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            color: LiveMessageColor.white,
            data: data is Map ? (data['text_large'] ?? data['count']) : data,
          );
        case 'ONLINE_RANK_COUNT':
          final data = obj['data'];
          return LiveMessageModel(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            color: LiveMessageColor.white,
            data: data is Map ? data['count'] : data,
          );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _readEmotes(dynamic payload) {
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    if (payload is String) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
