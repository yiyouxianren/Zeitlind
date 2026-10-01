import "dart:convert";
import "dart:io";
Future<void> main() async {
  final hc = HttpClient();
  // 老的直播搜索接口
  final req = await hc.getUrl(Uri.parse('https://api.live.bilibili.com/room/v3/index/search?platform=web&keyword=${Uri.encodeComponent('斯奎奇大王')}'));
  req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
  req.headers.set('Referer', 'https://live.bilibili.com/');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (body.contains('404')) {
    print('v3接口也404');
    return;
  }
  try {
    final j = jsonDecode(body);
    final result = (j['data']?['result'] ?? j['data']?['list'] ?? []) as List;
    for (final r in result.take(6)) {
      print('roomId=${r['roomid']} uname=${r['uname']} title=${r['title']} live=${r['live_status']}');
    }
  } catch (e) {
    print('失败: $e / ${body.substring(0, body.length > 200 ? 200 : body.length)}');
  }
}
