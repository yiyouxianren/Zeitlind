import 'package:pilipala/http/constants.dart';
import 'package:pilipala/http/init.dart';
import 'package:webview_cookie_manager/webview_cookie_manager.dart';

class SetCookie {
  static Future<void> onSet() async {
    final manager = WebviewCookieManager();
    for (final url in <String>[
      HttpString.baseUrl,
      HttpString.apiBaseUrl,
      HttpString.liveBaseUrl,
      HttpString.tUrl,
      HttpString.passBaseUrl,
      'https://m.bilibili.com',
      HttpString.messageBaseUrl,
    ]) {
      final cookies = await manager.getCookies(url);
      if (cookies.isNotEmpty) {
        await Request.cookieManager.cookieJar
            .saveFromResponse(Uri.parse(url), cookies);
      }
    }
  }
}
