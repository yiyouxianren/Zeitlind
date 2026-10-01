import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/cache_manage.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final AboutController _aboutController = Get.put(AboutController());
  String cacheSize = '';

  @override
  void initState() {
    super.initState();
    // 读取缓存占用
    getCacheSize();
  }

  Future<void> getCacheSize() async {
    final res = await CacheManage().loadApplicationCache();
    setState(() => cacheSize = res);
  }

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outline;
    TextStyle subTitleStyle =
        TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline);
    return Scaffold(
      appBar: AppBar(
        title: Text('关于', style: Theme.of(context).textTheme.titleMedium),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 应用图标（与桌面启动图标同源）
            Image.asset(
              'assets/images/logo/logo_app.png',
              width: 150,
            ),
            Text(
              '温柔の时间',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            // 版本号（纯展示，不提供任何下载入口）
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 30),
              child: Text(
                'V${_aboutController.currentVersion.value}',
                style: subTitleStyle.copyWith(
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            // 免责声明
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '本项目为个人练习Vibe coding的拙劣作品，仅供参考和学习，'
                  '可能存在未知的安全隐患，请勿下载和使用。'
                  '如果下载请在24H内删除',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            ListTile(
              onTap: () => _aboutController.logs(),
              title: const Text('错误日志'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16, color: outline),
            ),
            // 致谢：开源依赖与上游项目
            ListTile(
              onTap: () => Get.to(() => const AcknowledgementsPage()),
              title: const Text('致谢'),
              subtitle: Text('开源项目 · GLM · ZCode', style: subTitleStyle),
              trailing: Icon(Icons.arrow_forward_ios, size: 16, color: outline),
            ),
            ListTile(
              onTap: () async {
                var cleanStatus = await CacheManage().clearCacheAll();
                if (cleanStatus) {
                  getCacheSize();
                }
              },
              title: const Text('清除缓存'),
              subtitle: Text('图片及网络缓存 $cacheSize', style: subTitleStyle),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 20)
          ],
        ),
      ),
    );
  }
}

class AboutController extends GetxController {
  RxString currentVersion = ''.obs;

  @override
  void onInit() {
    super.onInit();
    getCurrentApp();
  }

  // 获取当前版本
  Future getCurrentApp() async {
    var result = await PackageInfo.fromPlatform();
    currentVersion.value = result.version;
  }

  // 日志
  logs() {
    Get.toNamed('/logs');
  }
}

/// 致谢页：本项目基于 pilipala 与 piliplus 衍生而来，
/// 并使用了众多优秀的开源项目与 AI 工具。
class AcknowledgementsPage extends StatelessWidget {
  const AcknowledgementsPage({super.key});

  static const List<Map<String, String>> _projects = <Map<String, String>>[
    {
      'name': 'pilipala',
      'desc': '上游项目 · 本应用基于其衍生',
      'url': 'https://github.com/guozhigq/pilipala',
    },
    {
      'name': 'piliplus',
      'desc': '上游项目 · 本应用基于其衍生',
      'url': 'https://github.com/bggRGjQaUbCoE/PiliPlus',
    },
    {
      'name': 'bilibili-API-collect',
      'desc': 'B 站接口文档整理',
      'url': 'https://github.com/SocialSisterYi/bilibili-API-collect',
    },
    {
      'name': 'flutter_meedu_videoplayer',
      'desc': '视频播放器',
      'url': 'https://github.com/zezo357/flutter_meedu_videoplayer',
    },
    {
      'name': 'ffmpeg_kit_flutter_new_audio',
      'desc': '音视频处理（下载合并）',
      'url': 'https://pub.dev/packages/ffmpeg_kit_flutter_new_audio',
    },
    {
      'name': 'media-kit',
      'desc': '多媒体播放内核',
      'url': 'https://github.com/media-kit/media-kit',
    },
    {
      'name': 'dio',
      'desc': '网络请求库',
      'url': 'https://github.com/cfug/dio',
    },
    {
      'name': '智谱 GLM-5.3 & ZCode',
      'desc': 'AI 编程助手 · 让编程小白也能基于开源项目做出自己的应用',
      'url': 'https://chatglm.cn',
    },
  ];

  void _open(String url) {
    launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outline;
    return Scaffold(
      appBar: AppBar(
        title: Text('致谢', style: Theme.of(context).textTheme.titleMedium),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              '本项目基于 pilipala 与 piliplus 衍生而来，'
              '感谢以下开源项目与服务的贡献：',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: outline,
              ),
            ),
          ),
          for (final Map<String, String> p in _projects)
            ListTile(
              onTap: () => _open(p['url']!),
              title: Text(p['name']!),
              subtitle: Text(
                '${p['desc']}\n${p['url']}',
                style: TextStyle(fontSize: 12, height: 1.4, color: outline),
              ),
              isThreeLine: true,
              trailing:
                  Icon(Icons.open_in_new, size: 18, color: outline),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }
}
