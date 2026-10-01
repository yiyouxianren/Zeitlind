import 'dart:convert';
import 'package:html/parser.dart';
import 'package:pilipala/models/read/opus.dart';
import 'package:pilipala/models/read/read.dart';
import 'package:pilipala/utils/wbi_sign.dart';
import 'index.dart';

class ReadHttp {
  static List<String> extractScriptContents(String htmlContent) {
    final scriptRegExp =
        RegExp(r'<script[^>]*>([\s\S]*?)</script>', caseSensitive: false);
    Iterable<Match> matches = scriptRegExp.allMatches(htmlContent);
    List<String> scriptContents = [];
    for (Match match in matches) {
      String scriptContent = match.group(1)!;
      scriptContents.add(scriptContent);
    }
    return scriptContents;
  }

  static Map<String, dynamic>? _extractEmbeddedObject(String html) {
    final scripts = extractScriptContents(html);
    for (final script in scripts) {
      var start = 0;
      while (start < script.length) {
        final objectStart = script.indexOf('{', start);
        if (objectStart < 0) break;
        var depth = 0;
        var inString = false;
        var escaped = false;
        for (var i = objectStart; i < script.length; i++) {
          final char = script[i];
          if (inString) {
            if (escaped) {
              escaped = false;
            } else if (char == r'\\') {
              escaped = true;
            } else if (char == '"') {
              inString = false;
            }
          } else if (char == '"') {
            inString = true;
          } else if (char == '{') {
            depth++;
          } else if (char == '}' && --depth == 0) {
            try {
              final value = json.decode(script.substring(objectStart, i + 1));
              final result = _findOpusState(value);
              if (result != null) return result;
            } catch (_) {}
            start = i + 1;
            break;
          }
        }
        if (depth != 0) break;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findOpusState(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final detail = map['detail'];
      if (detail is Map &&
          detail['basic'] is Map &&
          detail['modules'] is List) {
        return map;
      }
      for (final child in map.values) {
        final result = _findOpusState(child);
        if (result != null) return result;
      }
    } else if (value is List) {
      for (final child in value) {
        final result = _findOpusState(child);
        if (result != null) return result;
      }
    }
    return null;
  }

  // 解析专栏 opus格式
  static Future parseArticleOpus({required String id}) async {
    try {
      final res = await Request()
          .get('https://www.bilibili.com/opus/$id', extra: {'ua': 'pc'});
      final html = res.data?.toString() ?? '';
      final embedded = _extractEmbeddedObject(html);
      final candidate = embedded?['detail'] is Map
          ? embedded
          : embedded?['data'] is Map
              ? Map<String, dynamic>.from(embedded!['data'])
              : null;
      if (candidate != null && candidate['detail'] is Map) {
        return {'status': true, 'data': OpusDataModel.fromJson(candidate)};
      }
      return {
        'status': false,
        'data': OpusDataModel(),
        'msg': '专栏页面未返回可解析的结构化数据'
      };
    } catch (error) {
      return {'status': false, 'data': OpusDataModel(), 'msg': '专栏加载失败：$error'};
    }
  }

  // 解析专栏 cv格式
  static Future parseArticleCv({required String id}) async {
    var res = await Request().get(
      'https://www.bilibili.com/read/cv$id',
      extra: {'ua': 'pc'},
    );
    String scriptContent =
        extractScriptContents(parse(res.data).body!.outerHtml)[0];
    int startIndex = scriptContent.indexOf('{');
    int endIndex = scriptContent.lastIndexOf('};');
    String jsonContent = scriptContent.substring(startIndex, endIndex + 1);
    // 解析JSON字符串为Map
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    return {
      'status': true,
      'data': ReadDataModel.fromJson(jsonData),
    };
  }

  //
  static Future getViewInfo({required String id}) async {
    Map params = await WbiSign().makSign({
      'id': id,
      'mobi_app': 'pc',
      'from': 'web',
      'gaia_source': 'main_web',
      'web_location': 333.976,
    });
    var res = await Request().get(
      Api.getViewInfo,
      data: {
        'id': id,
        'mobi_app': 'pc',
        'from': 'web',
        'gaia_source': 'main_web',
        'web_location': 333.976,
        'w_rid': params['w_rid'],
        'wts': params['wts'],
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
}
