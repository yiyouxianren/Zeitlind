import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:pilipala/models/live/follow.dart';
import '../utils/wbi_sign.dart';

import '../models/live/item.dart';
import '../models/live/emote.dart';
import '../models/live/room_info.dart';
import '../models/live/room_info_h5.dart';
import 'api.dart';
import 'init.dart';

class LiveHttp {
  static Future liveList(
      {int? vmid, int? pn, int? ps, String? orderType}) async {
    final data = <String, dynamic>{
      'platform': 'web',
      'web_location': '444.7',
      if (pn != null) 'page': pn,
      if (ps != null) 'page_size': ps,
      if (orderType != null) 'order_type': orderType,
      if (vmid != null) 'vmid': vmid,
    };
    var res = await Request().get(
      Api.liveList,
      data: data,
      extra: {'referer': 'https://live.bilibili.com/'},
    );
    final response = res.data;
    if (response is Map && response['code'] == 0) {
      final rawData = response['data'];
      final roomModules = rawData is Map ? rawData['room_list'] : null;
      final recommendationModule = roomModules is List
          ? roomModules.whereType<Map>().cast<Map>().firstWhere(
                (module) => (module['module_info'] as Map?)?['title'] == '推荐直播',
                orElse: () => <String, dynamic>{},
              )
          : <String, dynamic>{};
      final moduleList = recommendationModule['list'];
      final rawList = moduleList is List
          ? moduleList
          : rawData is Map
              ? rawData['recommend_room_list']
              : null;
      if (rawList is! List) {
        return {
          'status': false,
          'data': <LiveItemModel>[],
          'msg': '直播推荐返回数据格式异常',
        };
      }
      try {
        return {
          'status': true,
          'data': rawList
              .whereType<Map>()
              .map<LiveItemModel>(
                  (e) => LiveItemModel.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        };
      } catch (error) {
        return {
          'status': false,
          'data': <LiveItemModel>[],
          'msg': '直播推荐解析失败: $error',
        };
      }
    } else {
      final code = response is Map ? response['code'] : null;
      final message =
          response is Map ? (response['message'] ?? response['msg']) : null;
      return {
        'status': false,
        'data': <LiveItemModel>[],
        'code': code,
        'msg': code == -352 ? 'B站风控校验失败，请检查登录状态或稍后重试' : (message ?? '直播推荐请求失败'),
      };
    }
  }

  static Future liveRoomInfo({roomId, qn, bool onlyAudio = false}) async {
    var res = await Request().get(Api.liveRoomInfo, data: {
      'room_id': roomId,
      'protocol': '0, 1',
      'format': '0, 1, 2',
      'codec': '0, 1',
      'qn': qn,
      'platform': 'web',
      'ptype': 8,
      'dolby': 5,
      'panorama': 1,
      if (onlyAudio) 'only_audio': 1,
    });
    if (res.data['code'] == 0) {
      return {'status': true, 'data': RoomInfoModel.fromJson(res.data['data'])};
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
      };
    }
  }

  static Future liveRoomInfoH5({roomId, qn}) async {
    var res = await Request().get(Api.liveRoomInfoH5, data: {
      'room_id': roomId,
    });
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': RoomInfoH5Model.fromJson(res.data['data'])
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
      };
    }
  }

  static Future getLiveEmoticons({required int roomId}) async {
    final res = await Request().get(
      Api.liveEmoticons,
      data: {
        'platform': 'pc',
        'room_id': roomId,
      },
      extra: {'referer': 'https://live.bilibili.com/$roomId'},
    );
    if (res.data is Map && res.data['code'] == 0) {
      final raw = res.data['data'];
      final List rawPackages;
      if (raw is Map && raw['data'] is List) {
        rawPackages = raw['data'] as List;
      } else if (raw is List) {
        rawPackages = raw;
      } else if (raw is Map && raw['emoticons'] is List) {
        rawPackages = [raw];
      } else {
        rawPackages = const [];
      }
      final packages = <LiveEmotePackage>[];
      for (final item in rawPackages) {
        if (item is! Map) continue;
        try {
          final package =
              LiveEmotePackage.fromJson(Map<String, dynamic>.from(item));
          if (package.emoticons.isNotEmpty) {
            packages.add(package);
          }
        } catch (_) {}
      }
      return {
        'status': true,
        'data': packages,
      };
    }
    return {
      'status': false,
      'data': <LiveEmotePackage>[],
      'msg': res.data is Map ? res.data['message'] : '获取直播间表情失败',
    };
  }

  // 获取弹幕信息
  static Future liveDanmakuInfo({roomId}) async {
    var res = await _requestDanmakuInfo(roomId, signed: true);
    if (res.data is Map && res.data['code'] != 0) {
      await WbiSign.clearCache();
      res = await _requestDanmakuInfo(roomId, signed: true);
    }
    if (res.data is Map && res.data['code'] != 0) {
      res = await _requestDanmakuInfo(roomId, signed: false);
    }
    if (res.data['code'] == 0) {
      final tokenText = res.data['data']?['token']?.toString() ?? '';
      debugPrint(
          'liveDanmakuInfo tokenLen=${tokenText.length} tokenHead=${tokenText.length > 20 ? tokenText.substring(0, 20) : tokenText}');
      return {
        'status': true,
        'data': res.data['data'],
      };
    } else {
      developer.log(
        'liveDanmakuInfo failed code=${res.data['code']} message=${res.data['message']} '
        'dataKeys=${res.data['data'] is Map ? (res.data['data'] as Map).keys.toList() : []}',
        name: 'LiveHttp',
      );
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
      };
    }
  }

  static Future<dynamic> _requestDanmakuInfo(
    dynamic roomId, {
    required bool signed,
  }) async {
    final params = <String, dynamic>{
      'id': roomId,
      'web_location': 444.8,
    };
    if (signed) {
      params.addAll(await WbiSign().makSign(params));
    }
    // 显式携带 cookie：认证 token 与登录态绑定，游客 token 无法通过弹幕服务器认证
    final cookieHeader = (await Request.cookieManager.cookieJar
            .loadForRequest(Uri.parse(Api.getDanmuInfo)))
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
    debugPrint(
        'getDanmuInfo cookies: ${cookieHeader.isNotEmpty ? cookieHeader.split(';').map((e) => e.trim().split('=').first).join(',') : 'none'}');
    return Request().get(
      Api.getDanmuInfo,
      data: params,
      extra: {
        'ua': 'pc',
        'referer': 'https://live.bilibili.com/$roomId',
        'cookie': cookieHeader,
      },
    );
  }

  static Future sendDanmaku({
    roomId,
    msg,
    int? dmType,
    String? emoticonOptions,
  }) async {
    final csrf = await Request.getCsrf();
    var res = await Request().post(
      Api.sendLiveMsg,
      data: {
        'bubble': 0,
        'msg': msg,
        'color': 16777215, // 颜色
        'mode': 1, // 模式
        if (dmType != null) 'dm_type': dmType,
        if (emoticonOptions != null) 'emoticonOptions': emoticonOptions,
        'room_type': 0,
        'jumpfrom': 71001, // 直播间来源
        'reply_mid': 0,
        'reply_attr': 0,
        'replay_dmid': '',
        'statistics': {"appId": 100, "platform": 5},
        'fontsize': 25, // 字体大小
        'rnd': DateTime.now().millisecondsSinceEpoch ~/ 1000, // 时间戳
        'roomid': roomId,
        'csrf': csrf,
        'csrf_token': csrf,
      },
    );
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data'],
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
      };
    }
  }

  // 我的关注 正在直播
  static Future liveFollowing({int? pn, int? ps}) async {
    var res = await Request().get(
      Api.liveList,
      data: {
        'platform': 'web',
        'web_location': '444.7',
      },
      extra: {'referer': 'https://live.bilibili.com/'},
    );
    final response = res.data;
    if (response is Map && response['code'] == 0) {
      final data = response['data'];
      final rooms = data is Map ? data['room_list'] : null;
      final followModule = rooms is List
          ? rooms.whereType<Map>().cast<Map>().firstWhere(
                (item) => (item['module_info'] is Map &&
                    (item['module_info']['type'] == 8 ||
                        item['module_info']['title'] == '我的关注')),
                orElse: () => <String, dynamic>{},
              )
          : <String, dynamic>{};
      final moduleInfo = followModule['module_info'];
      final rawList = followModule['list'];
      final list = rawList is List ? rawList : const <dynamic>[];
      return {
        'status': true,
        'data': LiveFollowingModel.fromJson({
          'list': list,
          'live_count': moduleInfo is Map ? moduleInfo['count'] : list.length,
        }),
      };
    }
    final code = response is Map ? response['code'] : null;
    final message =
        response is Map ? (response['message'] ?? response['msg']) : null;
    return {
      'status': false,
      'data': <LiveFollowingItemModel>[],
      'code': code,
      'msg': code == -352 ? 'B站风控校验失败，请检查登录状态或稍后重试' : (message ?? '关注直播请求失败'),
    };
  }

  // 直播历史记录
  static Future liveRoomEntry({required int roomId}) async {
    await Request().post(
      Api.liveRoomEntry,
      data: {
        'room_id': roomId,
        'platform': 'pc',
        'csrf_token': await Request.getCsrf(),
        'csrf': await Request.getCsrf(),
        'visit_id': '',
      },
    );
  }

  /// 我的粉丝牌列表：返回 [{medal_id, target_id(主播uid), medal_name, level, status(1=佩戴中), ...}]
  /// 接口异常时抛出带信息的异常，便于上层区分“没有粉丝牌”和“接口异常”。
  /// 注意：page_size 上限为 10（超过返回 1002002 参数异常），按 10/页翻页。
  static Future<List<Map<String, dynamic>>> fansMedalList() async {
    const int pageSize = 10;
    final List<Map<String, dynamic>> medals = [];
    int page = 1;
    while (true) {
      final res = await Request().get(
        Api.fansMedalList,
        data: {
          'page': page,
          'page_size': pageSize,
        },
        extra: {
          'ua': 'pc',
          'referer': 'https://live.bilibili.com/',
        },
      );
      final body = res.data;
      if (body is! Map || body['code'] != 0) {
        final code = body is Map ? body['code'] : null;
        final msg = body is Map ? (body['message'] ?? body['msg'] ?? '') : '响应格式异常';
        // -101 未登录 / -111 csrf 失效：明确抛错而非当作“暂无”
        throw Exception('粉丝牌接口返回异常 code=$code: $msg');
      }
      final data = body['data'];
      // GetMyMedals 返回 {items: [...], page_info: {total_page}, count}
      final List? list = data is Map ? (data['items'] ?? data['list']) : null;
      if (list == null || list.isEmpty) break;
      for (final item in list) {
        if (item is Map) {
          medals.add({
            'medal_id': _asInt(item['medal_id']) ?? 0,
            'target_id': _asInt(item['target_id']),
            'medal_name': (item['medal_name'] ?? item['name'] ?? '').toString(),
            'level': _asInt(item['level']),
            // status=1 表示当前佩戴中
            'status': _asInt(item['status']),
            'wear': _asInt(item['status']) == 1,
          });
        }
      }
      final pageInfo = data is Map && data['page_info'] is Map
          ? data['page_info'] as Map
          : const {};
      final totalPages = _asInt(pageInfo['total_page']);
      if (totalPages != null && page >= totalPages) break;
      if (list.length < pageSize) break;
      page++;
    }
    return medals;
  }

  /// 佩戴粉丝牌。medalId 传 0 表示取下当前佩戴。
  static Future<bool> wearFansMedal({required int medalId}) async {
    final csrf = await Request.getCsrf();
    final res = await Request().post(
      Api.wearFansMedal,
      data: {
        'medal_id': medalId,
        'csrf': csrf,
        'csrf_token': csrf,
      },
    );
    return res.data is Map && res.data['code'] == 0;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

}
