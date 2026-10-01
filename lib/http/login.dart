import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pilipala/http/constants.dart';
import 'package:uuid/uuid.dart';

import '../models/login/index.dart';
import '../utils/login.dart';
import 'index.dart';

class LoginHttp {
  static Map<String, dynamic> _map(dynamic value) {
    return value is Map<String, dynamic>
        ? value
        : value is Map
            ? Map<String, dynamic>.from(value)
            : <String, dynamic>{};
  }

  static String _message(Map<String, dynamic> data, [String fallback = '登录请求失败']) {
    final value = data['message'] ?? data['msg'] ?? data['error'];
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }

  static Map<String, dynamic> _result(Response response) {
    final body = _map(response.data);
    final code = body['code'];
    final data = _map(body['data']);
    return {
      'code': code,
      'body': body,
      'data': data,
      'message': _message(body),
    };
  }

  static Future<Map<String, dynamic>> queryCaptcha() async {
    final parsed = _result(await Request().get(Api.getCaptcha));
    if (parsed['code'] == 0) {
      return {
        'status': true,
        'data': CaptchaDataModel.fromJson(parsed['data']),
      };
    }
    return {'status': false, 'data': {}, 'msg': parsed['message']};
  }

  static Future<Map<String, dynamic>> sendWebSmsCode({
    int? cid,
    required String tel,
    required String token,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    final response = await Request().post(
      Api.webSmsCode,
      data: FormData.fromMap({
        'cid': cid,
        'tel': tel,
        'source': 'main_web',
        'token': token,
        'challenge': challenge,
        'validate': validate,
        'seccode': seccode,
      }),
    );
    final parsed = _result(response);
    if (parsed['code'] == 0) {
      return {'status': true, 'data': parsed['data']};
    }
    return {'status': false, 'data': {}, 'msg': parsed['message']};
  }

  static Future<Map<String, dynamic>> loginInByWebSmsCode({
    int? cid,
    required String tel,
    required String code,
    required String captchaKey,
  }) async {
    final response = await Request().post(
      Api.webSmsLogin,
      data: FormData.fromMap({
        'cid': cid,
        'tel': tel,
        'code': code,
        'source': 'main_mini',
        'keep': 0,
        'captcha_key': captchaKey,
        'go_url': HttpString.baseUrl,
      }),
    );
    final parsed = _result(response);
    if (parsed['code'] == 0) {
      return {'status': true, 'data': parsed['data']};
    }
    return {'status': false, 'data': {}, 'msg': parsed['message']};
  }

  static Future<Map<String, dynamic>> sendAppSmsCode({
    int? cid,
    required String tel,
    required String token,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    final data = <String, dynamic>{
      'cid': cid,
      'tel': tel,
      'login_session_id': const Uuid().v4().replaceAll('-', ''),
      'recaptcha_token': token,
      'gee_challenge': challenge,
      'gee_validate': validate,
      'gee_seccode': seccode,
      'channel': 'bili',
      'buvid': buvid(),
      'local_id': buvid(),
      'statistics': {
        'appId': 1,
        'platform': 3,
        'version': '7.52.0',
        'abtest': '',
      },
    };
    final parsed = _result(await Request().post(Api.appSmsCode, data: data));
    if (parsed['code'] == 0) {
      return {'status': true, 'data': parsed['data']};
    }
    return {'status': false, 'data': {}, 'msg': parsed['message']};
  }

  static String buvid() {
    final mac = <String>[];
    final random = Random();
    for (var i = 0; i < 6; i++) {
      mac.add(random.nextInt(256).toRadixString(16));
    }
    final md5Str = md5.convert(utf8.encode(mac.join(':'))).toString();
    final md5Arr = md5Str.split('');
    return 'XY${md5Arr[2]}${md5Arr[12]}${md5Arr[22]}$md5Str';
  }

  static Future<Map<String, dynamic>> getWebKey() async {
    final parsed = _result(await Request().get(
      Api.getWebKey,
      data: {'disable_rcmd': 0, 'local_id': LoginUtils.generateBuvid()},
    ));
    if (parsed['code'] == 0) {
      return {'status': true, 'data': parsed['data']};
    }
    return {'status': false, 'data': {}, 'msg': parsed['message']};
  }

  static Future<Map<String, dynamic>> loginInByMobPwd({
    required String tel,
    required String password,
    required String key,
    required String rhash,
  }) async {
    final publicKey = RSAKeyParser().parse(key) as RSAPublicKey;
    final encrypted = Encrypter(RSA(publicKey: publicKey))
        .encrypt(rhash + password)
        .base64;
    final parsed = _result(await Request().post(Api.loginInByPwdApi, data: {
      'username': tel,
      'password': encrypted,
      'local_id': LoginUtils.generateBuvid(),
      'disable_rcmd': '0',
    }));
    if (parsed['code'] == 0) {
      return {'status': true, 'data': parsed['data']};
    }
    return {'status': false, 'data': parsed['data'], 'msg': parsed['message']};
  }

  static Future<Map<String, dynamic>> loginInByWebPwd({
    required String username,
    required String password,
    required String token,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    final response = await Request().post(
      Api.loginInByWebPwd,
      data: FormData.fromMap({
        'username': username,
        'password': password,
        'keep': 0,
        'token': token,
        'challenge': challenge,
        'validate': validate,
        'seccode': seccode,
        'source': 'main-fe-header',
        'go_url': HttpString.baseUrl,
      }),
    );
    final parsed = _result(response);
    if (parsed['code'] == 0) {
      final status = parsed['data']['status'];
      if (status == null || status == 0) {
        return {'status': true, 'data': parsed['data']};
      }
      final nested = _map(parsed['data']['data']);
      final url = parsed['data']['url'] ?? nested['url'];
      return {
        'status': false,
        'code': 1,
        'data': parsed['data'],
        'url': url,
        'msg': _message(parsed['data'], '需要完成官方安全验证'),
      };
    }
    return {
      'status': false,
      'data': parsed['data'],
      'msg': parsed['message'],
      'risk': parsed['code'] == -352,
    };
  }

  static Future<Map<String, dynamic>> getWebQrcode() async {
    final parsed = _result(await Request().get(Api.qrCodeApi));
    if (parsed['code'] == 0) {
      return {'status': true, 'data': parsed['data']};
    }
    return {'status': false, 'data': {}, 'msg': parsed['message']};
  }

  static Future<Map<String, dynamic>> queryWebQrcodeStatus(String qrcodeKey) async {
    final parsed = _result(await Request().get(
      Api.loginInByQrcode,
      data: {'qrcode_key': qrcodeKey},
    ));
    final code = _map(parsed['data'])['code'] ?? parsed['code'];
    if (code == 0) {
      return {'status': true, 'state': 'success', 'data': parsed['data']};
    }
    if (code == 86090) {
      return {'status': false, 'state': 'scanned', 'data': parsed['data']};
    }
    if (code == 86038) {
      return {'status': false, 'state': 'expired', 'data': parsed['data'], 'msg': '二维码已过期'};
    }
    return {
      'status': false,
      'state': 'waiting',
      'data': parsed['data'],
      'msg': parsed['message'],
    };
  }
}
