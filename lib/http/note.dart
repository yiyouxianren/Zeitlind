import 'dart:convert';

import 'package:dio/dio.dart';

import 'api.dart';
import 'init.dart';

/// 笔记（图文评论）API
class NoteHttp {
  /// 发布笔记
  /// [title] 标题 / [summary] 摘要（纯文本正文）
  /// [banners] 已上传的图片信息列表 [{img_width, img_height, img_size, img_src}]
  /// [oid]/[replyType] 关联的视频评论区（发布后在对应视频评论区展示）
  static Future addNote({
    required String title,
    required String summary,
    List? banners,
    int? oid,
    int? replyType,
  }) async {
    String csrf = await Request.getCsrf();
    final Map<String, dynamic> data = {
      'title': title,
      'summary': summary,
      'banners': banners ?? [],
      'type': 1,
      'reply_type': replyType ?? 1,
      if (oid != null) 'oid': oid,
      'csrf': csrf,
    };
    var res = await Request().post(
      Api.addNote,
      data: data,
      options: Options(contentType: 'application/json'),
    );
    // multipart/JSON 场景响应可能为 String，统一处理
    final dynamic rawData = res.data;
    final Map<String, dynamic> json = rawData is String
        ? jsonDecode(rawData) as Map<String, dynamic>
        : Map<String, dynamic>.from(rawData as Map);
    if (json['code'] == 0) {
      return {'status': true, 'data': json['data']};
    } else {
      return {
        'status': false,
        'msg': (json['message'] ?? '发布失败').toString()
      };
    }
  }
}
