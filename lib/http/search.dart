import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:pilipala/models/search/all.dart';
import 'package:pilipala/utils/wbi_sign.dart';
import '../models/bangumi/info.dart';
import '../models/common/search_type.dart';
import '../models/search/hot.dart';
import '../models/search/result.dart';
import '../models/search/suggest.dart';
import '../utils/blacklist_filter.dart';
import '../utils/keyword_filter.dart';
import 'index.dart';

class SearchHttp {
  static Future hotSearchList() async {
    var res = await Request().get(Api.hotSearchList);
    if (res.data is String) {
      Map<String, dynamic> resultMap = json.decode(res.data);
      if (resultMap['code'] == 0) {
        return {
          'status': true,
          'data': HotSearchModel.fromJson(resultMap),
        };
      }
    } else if (res.data is Map<String, dynamic> && res.data['code'] == 0) {
      return {
        'status': true,
        'data': HotSearchModel.fromJson(res.data),
      };
    }

    return {
      'status': false,
      'data': [],
      'msg': '请求错误 🙅',
    };
  }

  // 获取搜索建议
  static Future searchSuggest({required term}) async {
    var res = await Request().get(Api.searchSuggest,
        data: {'term': term, 'main_ver': 'v1', 'highlight': term});
    if (res.data is String) {
      Map<String, dynamic> resultMap = json.decode(res.data);
      if (resultMap['code'] == 0) {
        if (resultMap['result'] is Map) {
          resultMap['result']['term'] = term;
        }
        return {
          'status': true,
          'data': resultMap['result'] is Map
              ? SearchSuggestModel.fromJson(resultMap['result'])
              : [],
        };
      } else {
        return {
          'status': false,
          'data': [],
          'msg': '请求错误 🙅',
        };
      }
    } else {
      return {
        'status': false,
        'data': [],
        'msg': '请求错误 🙅',
      };
    }
  }

  // 分类搜索
  static Future searchByType({
    required SearchType searchType,
    required String keyword,
    required page,
    String? order,
    int? duration,
    int? tids,
  }) async {
    var reqData = {
      'search_type': searchType.type,
      'keyword': keyword,
      // 'order_sort': 0,
      // 'user_type': 0,
      'page': page,
      if (order != null) 'order': order,
      if (duration != null) 'duration': duration,
      if (tids != null && tids != -1) 'tids': tids,
    };
    var res = await Request().get(Api.searchByType, data: reqData);
    if (res.data['code'] == 0) {
      if (res.data['data']['numPages'] == 0) {
        // 我想返回数据，使得可以通过data.list 取值，结果为[]
        return {'status': true, 'data': Data()};
      }
      Object data;
      try {
        switch (searchType) {
          case SearchType.video:
            final result = (res.data['data']['result'] as Iterable?)
                    ?.where((item) =>
                        item is Map &&
                        !BlacklistFilter.isBlocked(item['mid']) &&
                        !KeywordFilter.shouldBlock(
                          title: item['title'],
                          description: item['description'],
                          tags: item['tag'],
                          ownerName: item['author'],
                        ))
                    .toList() ??
                [];
            final dataMap = Map<String, dynamic>.from(res.data['data']);
            dataMap['result'] = result;
            data = SearchVideoModel.fromJson(dataMap);
            break;
          case SearchType.live_room:
            data = SearchLiveModel.fromJson(res.data['data']);
            break;
          case SearchType.bili_user:
            // 用户搜索结果：过滤黑名单用户及昵称命中关键词屏蔽的条目
            final result = (res.data['data']['result'] as Iterable?)
                    ?.where((item) =>
                        item is Map &&
                        !BlacklistFilter.isBlocked(item['mid']) &&
                        !KeywordFilter.shouldBlock(
                          title: item['uname'],
                          description: item['usign'],
                        ))
                    .toList() ??
                [];
            final userMap = Map<String, dynamic>.from(res.data['data']);
            userMap['result'] = result;
            data = SearchUserModel.fromJson(userMap);
            break;
          case SearchType.media_bangumi:
            data = SearchMBangumiModel.fromJson(res.data['data']);
            break;
          case SearchType.article:
            data = SearchArticleModel.fromJson(res.data['data']);
            break;
        }
        return {
          'status': true,
          'data': data,
        };
      } catch (err) {
        print(err);
      }
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
      };
    }
  }

  static Future<int> ab2c({int? aid, String? bvid}) async {
    Map<String, dynamic> data = {};
    if (aid != null) {
      data['aid'] = aid;
    } else if (bvid != null) {
      data['bvid'] = bvid;
    }
    final dynamic res =
        await Request().get(Api.ab2c, data: <String, dynamic>{...data});
    if (res.data['code'] == 0) {
      return res.data['data'].first['cid'];
    } else {
      return -1;
    }
  }

  static Future<Map<String, dynamic>> bangumiInfo(
      {int? seasonId, int? epId}) async {
    final Map<String, dynamic> data = {};
    if (seasonId != null) {
      data['season_id'] = seasonId;
    }
    if (epId != null) {
      data['ep_id'] = epId;
    }
    final dynamic res =
        await Request().get(Api.bangumiInfo, data: <String, dynamic>{...data});
    if (res.data['code'] == 0) {
      final rawResult = res.data['result'] ?? res.data['data'];
      if (rawResult is! Map) {
        return {'status': false, 'data': [], 'msg': '番剧返回数据格式异常'};
      }
      final parsed = BangumiInfoModel.fromJson(
        Map<String, dynamic>.from(rawResult),
      );
      if ((parsed.episodes ?? []).isEmpty && parsed.seasonId != null) {
        return {
          'status': false,
          'data': parsed,
          'msg': '番剧没有可播放分集',
        };
      }
      return {
        'status': true,
        'data': parsed,
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': '请求错误 🙅',
      };
    }
  }

  static Future<Map<String, dynamic>> ab2cWithPic(
      {int? aid, String? bvid}) async {
    Map<String, dynamic> data = {};
    if (aid != null) {
      data['aid'] = aid;
    } else if (bvid != null) {
      data['bvid'] = bvid;
    }
    final dynamic res =
        await Request().get(Api.ab2c, data: <String, dynamic>{...data});
    return {
      'cid': res.data['data'].first['cid'],
      'pic': res.data['data'].first['first_frame'],
    };
  }

  static Future<Map<String, dynamic>> searchCount(
      {required String keyword}) async {
    Map<String, dynamic> data = {
      'keyword': keyword,
      'web_location': 333.999,
    };
    Map params = await WbiSign().makSign(data);
    final dynamic res = await Request().get(Api.searchCount, data: params);
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': SearchAllModel.fromJson(res.data['data']),
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': '请求错误 🙅',
      };
    }
  }

  /// 综合搜索（与网页端一致）：返回置顶 UP 主（bili_user）+ 视频等 block。
  /// 与 [searchCount] 同一端点，模型里额外解析了 users / videos。
  static Future<Map<String, dynamic>> searchAll(
      {required String keyword}) async {
    Map<String, dynamic> data = {
      'keyword': keyword,
      'web_location': 333.999,
    };
    Map params = await WbiSign().makSign(data);
    final dynamic res = await Request().get(Api.searchCount, data: params);
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': SearchAllModel.fromJson(res.data['data']),
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'] ?? '请求错误 🙅',
      };
    }
  }
}

class Data {
  List<dynamic> list;

  Data({this.list = const []});
}
