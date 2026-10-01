// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
// import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/utils/id_utils.dart';
import '../models/user/info.dart';
import '../utils/storage.dart';
import '../utils/utils.dart';
import 'api.dart';
import 'constants.dart';
import 'interceptor.dart';

class Request {
  static final Request _instance = Request._internal();
  static late CookieManager cookieManager;
  static late final Dio dio;
  factory Request() => _instance;
  Box setting = GStrorage.setting;
  static Box localCache = GStrorage.localCache;
  late bool enableSystemProxy;
  late String systemProxyHost;
  late String systemProxyPort;
  static final RegExp spmPrefixExp =
      RegExp(r'<meta name="spm_prefix" content="([^"]+?)">');
  static String? buvid;

  /// 设置cookie
  static setCookie() async {
    Box userInfoCache = GStrorage.userInfo;
    Box setting = GStrorage.setting;
    final String cookiePath = await Utils.getCookiePath();
    final PersistCookieJar cookieJar = PersistCookieJar(
      storage: FileStorage(cookiePath),
    );
    cookieManager = CookieManager(cookieJar);
    dio.interceptors.add(cookieManager);
    final userInfo = userInfoCache.get('userInfoCache');
    if (userInfo != null && userInfo.mid != null) {
      final List<Cookie> cookie2 = await cookieManager.cookieJar
          .loadForRequest(Uri.parse(HttpString.tUrl));
      if (cookie2.isEmpty) {
        try {
          await Request().get(HttpString.tUrl);
        } catch (e) {
          log("setCookie, ${e.toString()}");
        }
      }
    }
    setOptionsHeaders(userInfo, userInfo != null && userInfo.mid != null);
    await _refreshLoginCache();
    String baseUrlType = 'default';
    if (setting.get(SettingBoxKey.enableGATMode, defaultValue: false)) {
      baseUrlType = 'bangumi';
    }
    setBaseUrl(type: baseUrlType);
    try {
      await buvidActivate();
    } catch (e) {
      log("setCookie, ${e.toString()}");
    }
  }

  static Future<void> _refreshLoginCache() async {
    try {
      final response = await Request().get(Api.userInfo);
      final data = response.data;
      if (data is Map && data['code'] == 0 && data['data'] is Map) {
        final user = data['data'];
        final isLogin = user['isLogin'] == true ||
            user['isLogin'] == 1 ||
            user['isLogin']?.toString().toLowerCase() == 'true';
        if (isLogin && user['mid'] != null) {
          await GStrorage.userInfo.put(
            'userInfoCache',
            UserInfoData.fromJson(Map<String, dynamic>.from(user)),
          );
          setOptionsHeaders(
            GStrorage.userInfo.get('userInfoCache'),
            true,
          );
        } else {
          await GStrorage.userInfo.delete('userInfoCache');
          setOptionsHeaders(null, false);
        }
      }
    } catch (e) {
      log('refresh login cache failed: $e');
    }
  }

  // 从cookie中获取 csrf token
  static Future<String> getCsrf() async {
    final List<Cookie> cookies = await cookieManager.cookieJar
        .loadForRequest(Uri.parse(HttpString.apiBaseUrl));
    for (final Cookie cookie in cookies) {
      if (cookie.name == 'bili_jct' && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    return '';
  }

  static Future<String> requireAuthenticatedCsrf() async {
    if (!await hasValidSession()) {
      return '';
    }
    return getCsrf();
  }

  static Future<bool> hasValidSession() async {
    final userInfo = GStrorage.userInfo.get('userInfoCache');
    return userInfo is UserInfoData &&
        userInfo.isLogin == true &&
        userInfo.mid != null;
  }

  static Future<Map<String, dynamic>> authData({
    bool csrfToken = false,
  }) async {
    final csrf = await getCsrf();
    if (csrf.isEmpty) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{
      'csrf': csrf,
      if (csrfToken) 'csrf_token': csrf,
    };
  }

  static Future<String> getBuvid() async {
    if (buvid != null) {
      return buvid!;
    }

    final List<Cookie> cookies = await cookieManager.cookieJar
        .loadForRequest(Uri.parse(HttpString.baseUrl));
    for (final Cookie cookie in cookies) {
      if (cookie.name == 'buvid3') {
        buvid = cookie.value;
        break;
      }
    }
    if (buvid == null || buvid!.isEmpty) {
      try {
        var result = await Request().get(
          "${HttpString.apiBaseUrl}/x/frontend/finger/spi",
        );
        buvid = result.data?["data"]?["b_3"]?.toString() ?? '';
      } catch (_) {
        buvid = '';
        log('Unable to fetch buvid fallback', name: 'Request');
      }
    }

    return buvid!;
  }

  static setOptionsHeaders(userInfo, bool status) {
    if (status) {
      dio.options.headers['x-bili-mid'] = userInfo.mid.toString();
      dio.options.headers['x-bili-aurora-eid'] =
          IdUtils.genAuroraEid(userInfo.mid);
    } else {
      dio.options.headers.remove('x-bili-mid');
      dio.options.headers.remove('x-bili-aurora-eid');
    }
    dio.options.headers.addAll(<String, dynamic>{
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9',
      'env': 'prod',
      'referer': 'https://www.bilibili.com/',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
      'x-bili-aurora-zone': 'sh001',
    });
  }

  static Future buvidActivate() async {
    var html = await Request().get(Api.dynamicSpmPrefix);
    String spmPrefix = spmPrefixExp.firstMatch(html.data)!.group(1)!;
    Random rand = Random();
    String randPngEnd = base64.encode(
        List<int>.generate(32, (_) => rand.nextInt(256)) +
            List<int>.filled(4, 0) +
            [73, 69, 78, 68] +
            List<int>.generate(4, (_) => rand.nextInt(256)));

    String jsonData = json.encode({
      '3064': 1,
      '39c8': '$spmPrefix.fp.risk',
      '3c43': {
        'adca': 'Linux',
        'bfe9': randPngEnd.substring(randPngEnd.length - 50),
      },
    });

    await Request().post(Api.activateBuvidApi,
        data: {'payload': jsonData},
        options: Options(contentType: 'application/json'));
  }

  /*
   * config it and create
   */
  Request._internal() {
    //BaseOptions、Options、RequestOptions 都可以配置参数，优先级别依次递增，且可以根据优先级别覆盖参数
    BaseOptions options = BaseOptions(
      //请求基地址,可以包含子路径
      baseUrl: HttpString.apiBaseUrl,
      //连接服务器超时时间，单位是毫秒.
      connectTimeout: const Duration(milliseconds: 12000),
      //响应流上前后两次接受到数据的间隔，单位为毫秒。
      receiveTimeout: const Duration(milliseconds: 12000),
      //Http请求头.
      headers: {},
    );

    enableSystemProxy = setting.get(SettingBoxKey.enableSystemProxy,
        defaultValue: false) as bool;
    systemProxyHost =
        localCache.get(LocalCacheKey.systemProxyHost, defaultValue: '');
    systemProxyPort =
        localCache.get(LocalCacheKey.systemProxyPort, defaultValue: '');

    dio = Dio(options);

    /// fix 第三方登录 302重定向 跟iOS代理问题冲突
    // ..httpClientAdapter = Http2Adapter(
    //   ConnectionManager(
    //     idleTimeout: const Duration(milliseconds: 10000),
    //     onClientCreate: (_, ClientSetting config) =>
    //         config.onBadCertificate = (_) => true,
    //   ),
    // );

    /// 设置代理
    if (enableSystemProxy) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final HttpClient client = HttpClient();
          // Config the client.
          client.findProxy = (Uri uri) {
            // return 'PROXY host:port';
            return 'PROXY $systemProxyHost:$systemProxyPort';
          };
          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
          return client;
        },
      );
    }

    //添加拦截器
    dio.interceptors.add(ApiInterceptor());

    // 日志拦截器 输出请求、响应内容
    dio.interceptors.add(LogInterceptor(
      request: false,
      requestHeader: false,
      responseHeader: false,
    ));

    dio.transformer = BackgroundTransformer();
    dio.options.validateStatus = (int? status) {
      return status! >= 200 && status < 300 ||
          HttpString.validateStatusCodes.contains(status);
    };
  }

  /*
   * get请求
   */
  get(url, {data, options, cancelToken, extra}) async {
    Response response;
    final Options options = Options();
    ResponseType resType = ResponseType.json;
    if (extra != null) {
      resType = extra!['resType'] ?? ResponseType.json;
      final Map<String, dynamic> headers = <String, dynamic>{};
      if (extra['ua'] != null) {
        headers['user-agent'] = headerUa(type: extra['ua']);
      }
      if (extra['referer'] != null) {
        headers['referer'] = extra['referer'];
      }
      if (extra['cookie'] != null && extra['cookie'] is String) {
        headers['cookie'] = extra['cookie'];
      }
      if (headers.isNotEmpty) {
        options.headers = headers;
      }
    }
    options.responseType = resType;

    try {
      response = await dio.get(
        url,
        queryParameters: data,
        options: options,
        cancelToken: cancelToken,
      );
      await _logBusinessFailure(response);
      return response;
    } on DioException catch (e) {
      return _dioErrorResponse(e);
    }
  }

  /*
   * post请求
   */
  post(url, {data, queryParameters, options, cancelToken, extra}) async {
    if (data is Map &&
        (data.containsKey('csrf') || data.containsKey('csrf_token'))) {
      final csrf = data['csrf'] ?? data['csrf_token'];
      if (csrf is! String || csrf.isEmpty || !await hasValidSession()) {
        return Response<dynamic>(
          data: <String, dynamic>{
            'code': -101,
            'status': false,
            'message': '登录状态已失效，请重新登录',
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: url.toString()),
        );
      }
    }
    Response response;
    try {
      response = await dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options:
            options ?? Options(contentType: Headers.formUrlEncodedContentType),
        cancelToken: cancelToken,
      );
      await _logBusinessFailure(response);
      // print('post success: ${response.data}');
      return response;
    } on DioException catch (e) {
      return _dioErrorResponse(e);
    }
  }

  static Future<Response<dynamic>> _dioErrorResponse(
    DioException error,
  ) async {
    final String message = await ApiInterceptor.dioError(error);
    await _logDioError(error, message);
    return Response<dynamic>(
      data: <String, dynamic>{
        'code': -1,
        'status': false,
        'message': message,
      },
      statusCode: 200,
      requestOptions: error.requestOptions,
    );
  }

  static Future<void> _logBusinessFailure(Response<dynamic> response) async {
    final dynamic data = response.data;
    if (data is! Map || data['code'] != -352) {
      return;
    }

    final Uri uri = response.requestOptions.uri;
    log(
      jsonEncode(<String, dynamic>{
        'event': 'bilibili_business_error',
        'host': uri.host,
        'path': uri.path,
        'code': data['code'],
        'message': _safeDiagnosticText(data['message'] ?? data['msg']),
        'responseKeys': data.keys.map((key) => key.toString()).toList()..sort(),
        'cookieNames': await _cookieNamesFor(uri),
      }),
      name: 'Request',
    );
  }

  static Future<void> _logDioError(
    DioException error,
    String fallbackMessage,
  ) async {
    final Uri uri = error.requestOptions.uri;
    final dynamic responseData = error.response?.data;
    final Map<dynamic, dynamic>? responseMap =
        responseData is Map ? responseData : null;
    final List<String> responseKeys =
        responseMap?.keys.map((key) => key.toString()).toList() ?? <String>[];
    responseKeys.sort();
    log(
      jsonEncode(<String, dynamic>{
        'event': 'dio_error',
        'host': uri.host,
        'path': uri.path,
        'type': error.type.name,
        'httpStatus': error.response?.statusCode,
        'code': responseMap?['code'] ?? -1,
        'message': _safeDiagnosticText(
          responseMap?['message'] ?? responseMap?['msg'] ?? fallbackMessage,
        ),
        'responseKeys': responseKeys,
        'cookieNames': await _cookieNamesFor(uri),
      }),
      name: 'Request',
    );
  }

  static Future<List<String>> _cookieNamesFor(Uri uri) async {
    try {
      final List<String> names = (await cookieManager.cookieJar
              .loadForRequest(uri))
          .map((Cookie cookie) => cookie.name)
          .toSet()
          .toList()
        ..sort();
      return names;
    } catch (_) {
      return <String>[];
    }
  }

  static String _safeDiagnosticText(dynamic value) {
    final String text = (value ?? '').toString().replaceAll(
          RegExp(r'[\r\n\t]+'),
          ' ',
        );
    return text.length <= 200 ? text : text.substring(0, 200);
  }

  /*
   * 下载文件
   */
  downloadFile(urlPath, savePath) async {
    Response response;
    try {
      response = await dio.download(urlPath, savePath,
          onReceiveProgress: (int count, int total) {
        //进度
        // print("$count $total");
      });
      print('downloadFile success: ${response.data}');

      return response.data;
    } on DioException catch (e) {
      print('downloadFile error: $e');
      return Future.error(ApiInterceptor.dioError(e));
    }
  }

  /*
   * 取消请求
   *
   * 同一个cancel token 可以用于多个请求，当一个cancel token取消时，所有使用该cancel token的请求都会被取消。
   * 所以参数可选
   */
  void cancelRequests(CancelToken token) {
    token.cancel("cancelled");
  }

  String headerUa({type = 'mob'}) {
    String headerUa = '';
    if (type == 'mob') {
      if (Platform.isIOS) {
        headerUa =
            'Mozilla/5.0 (iPhone; CPU iPhone OS 14_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1 Mobile/15E148 Safari/604.1';
      } else {
        headerUa =
            'Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.101 Mobile Safari/537.36';
      }
    } else {
      headerUa =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
    }
    return headerUa;
  }

  static setBaseUrl({String type = 'default'}) {
    switch (type) {
      case 'default':
        dio.options.baseUrl = HttpString.apiBaseUrl;
        break;
      case 'bangumi':
        dio.options.baseUrl = HttpString.bangumiBaseUrl;
        break;
      default:
        dio.options.baseUrl = HttpString.apiBaseUrl;
    }
  }
}
