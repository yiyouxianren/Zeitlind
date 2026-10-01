import 'dart:math';
import 'package:dio/dio.dart';
import '../models/dynamics/result.dart';
import '../models/dynamics/up.dart';
import 'index.dart';

class DynamicsHttp {
  static Future followDynamic({
    String? type,
    int? page,
    String? offset,
    int? mid,
  }) async {
    var currentOffset = page == 1 ? '' : (offset ?? '').trim();
    final visitedOffsets = <String>{currentOffset};

    for (var requestCount = 0; requestCount < 4; requestCount++) {
      final requestPage = page ?? 1;
      final data = <String, dynamic>{
        'type': type ?? 'all',
        'offset': currentOffset,
        'page': requestPage,
        'timezone_offset': -480,
        'features': 'itemOpusStyle,listOnlyfans,onlyfansQaCard',
      };
      if (mid != null && mid != -1) {
        data['host_mid'] = mid;
      }

      final res = await Request().get(
        Api.followDynamic,
        data: data,
        extra: {'referer': 'https://t.bilibili.com/'},
      );
      final response = res.data;
      if (response is! Map || response['code'] != 0) {
        final code = response is Map ? response['code'] : null;
        final message =
            response is Map ? (response['message'] ?? response['msg']) : null;
        return {
          'status': false,
          'data': <DynamicItemModel>[],
          'msg': code == -352 ? 'B站风控校验失败，请检查登录状态或稍后重试' : (message ?? '动态请求失败'),
          'code': code,
        };
      }

      try {
        final rawData = response['data'];
        if (rawData is! Map) {
          return {
            'status': false,
            'data': <DynamicItemModel>[],
            'msg': '动态返回数据格式异常',
          };
        }
        final parsed = DynamicsDataModel.fromJson(
          Map<String, dynamic>.from(rawData),
        );
        final nextOffset = parsed.offset?.trim() ?? '';
        if (parsed.loadNext == true &&
            nextOffset.isNotEmpty &&
            visitedOffsets.add(nextOffset)) {
          currentOffset = nextOffset;
          page = requestPage + 1;
          continue;
        }
        return {'status': true, 'data': parsed};
      } catch (err) {
        return {
          'status': false,
          'data': <DynamicItemModel>[],
          'msg': '动态解析失败: $err',
        };
      }
    }

    return {
      'status': false,
      'data': <DynamicItemModel>[],
      'msg': '动态分页游标异常，请稍后重试',
    };
  }

  static Future followUp() async {
    var res = await Request().get(
      Api.followUp,
      data: {
        'up_list_more': 1,
        'web_location': '333.1365',
      },
      extra: {'referer': 'https://t.bilibili.com/'},
    );
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': FollowUpModel.fromJson(res.data['data']),
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
      };
    }
  }

  // 动态点赞
  static Future likeDynamic({
    required String? dynamicId,
    required int? up,
  }) async {
    var res = await Request().post(
      Api.likeDynamic,
      data: {
        'dynamic_id': dynamicId,
        'up': up,
        'csrf': await Request.getCsrf(),
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

  //
  static Future dynamicDetail({
    String? id,
  }) async {
    var res = await Request().get(Api.dynamicDetail, data: {
      'timezone_offset': -480,
      'id': id,
      'features': 'itemOpusStyle',
    });
    if (res.data['code'] == 0) {
      try {
        return {
          'status': true,
          'data': DynamicItemModel.fromJson(res.data['data']['item']),
        };
      } catch (err) {
        return {
          'status': false,
          'data': [],
          'msg': err.toString(),
        };
      }
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
      };
    }
  }

  static Future dynamicForward() async {
    var res = await Request().post(
      Api.dynamicForwardUrl,
      queryParameters: {
        'csrf': await Request.getCsrf(),
        'x-bili-device-req-json': {'platform': 'web', 'device': 'pc'},
        'x-bili-web-req-json': {'spm_id': '333.999'},
      },
      data: {
        'attach_card': null,
        'scene': 4,
        'content': {
          'conetents': [
            {'raw_text': "2", 'type': 1, 'biz_id': ""}
          ]
        }
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

  static Future dynamicCreate({
    required int mid,
    required int scene,
    int? oid,
    String? dynIdStr,
    String? rawText,
  }) async {
    DateTime now = DateTime.now();
    int timestamp = now.millisecondsSinceEpoch ~/ 1000;
    Random random = Random();
    int randomNumber = random.nextInt(9000) + 1000;
    String uploadId = '${mid}_${timestamp}_$randomNumber';

    Map<String, dynamic> webRepostSrc = {
      'dyn_id_str': dynIdStr ?? '',
    };

    /// 投稿转发
    if (scene == 5) {
      webRepostSrc = {
        'revs_id': {'dyn_type': 8, 'rid': oid}
      };
    }
    var res = await Request().post(
      Api.dynamicCreate,
      queryParameters: {
        'platform': 'web',
        'csrf': await Request.getCsrf(),
        'x-bili-device-req-json': {'platform': 'web', 'device': 'pc'},
        'x-bili-web-req-json': {'spm_id': '333.999'},
      },
      data: {
        'dyn_req': {
          'content': {
            'contents': [
              {'raw_text': rawText ?? '', 'type': 1, 'biz_id': ''}
            ]
          },
          'scene': scene,
          'attach_card': null,
          'upload_id': uploadId,
          'meta': {
            'app_meta': {'from': 'create.dynamic.web', 'mobi_app': 'web'}
          }
        },
        'web_repost_src': webRepostSrc
      },
      options: Options(contentType: 'application/json'),
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

  /// @用户联想搜索（评论/动态发布时选择@对象）
  /// 返回 [{'face', 'name', 'uid', 'fans'}]
  static Future dynMention({String? keyword}) async {
    try {
      var res = await Request().get(
        '/x/polymer/web-dynamic/v1/mention/search',
        data: {
          if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
          'web_location': '333.1365',
        },
      );
      if (res.data['code'] == 0 && res.data['data'] is Map) {
        final List items = [];
        final groups = res.data['data']['groups'];
        if (groups is List) {
          for (final g in groups) {
            final gItems = g is Map ? g['items'] : null;
            if (gItems is List) items.addAll(gItems);
          }
        }
        return {
          'status': true,
          'data': items,
        };
      } else {
        return {
          'status': false,
          'data': <Map>[],
          'msg': (res.data['message'] ?? '搜索失败').toString(),
        };
      }
    } catch (e) {
      return {'status': false, 'data': <Map>[], 'msg': e.toString()};
    }
  }
}
