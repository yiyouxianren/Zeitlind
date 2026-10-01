import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/member.dart';
import 'package:pilipala/pages/setting/widgets/switch_item.dart';
import 'package:pilipala/utils/keyword_filter.dart';
import 'package:pilipala/utils/storage.dart';

class PrivacySetting extends StatefulWidget {
  const PrivacySetting({super.key});

  @override
  State<PrivacySetting> createState() => _PrivacySettingState();
}

class _PrivacySettingState extends State<PrivacySetting> {
  bool userLogin = false;
  Box userInfoCache = GStrorage.userInfo;
  var userInfo;

  @override
  void initState() {
    super.initState();
    userInfo = userInfoCache.get('userInfoCache');
    userLogin = userInfo != null;
  }

  @override
  Widget build(BuildContext context) {
    TextStyle titleStyle = Theme.of(context).textTheme.titleMedium!;
    TextStyle subTitleStyle = Theme.of(context)
        .textTheme
        .labelMedium!
        .copyWith(color: Theme.of(context).colorScheme.outline);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          '隐私设置',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: Column(
        children: [
          ListTile(
            onTap: () {
              if (!userLogin) {
                SmartDialog.showToast('登录后查看');
                return;
              }
              Get.toNamed('/blackListPage');
            },
            dense: false,
            title: Text('黑名单管理', style: titleStyle),
            subtitle: Text('已拉黑用户', style: subTitleStyle),
          ),
          const SetSwitchItem(
            title: '彻底屏蔽黑名单用户',
            subTitle: '首页、排行榜和搜索结果中隐藏黑名单用户的视频',
            setKey: SettingBoxKey.enableBlacklistFilter,
            defaultVal: true,
          ),
          const SetSwitchItem(
            title: '关键词屏蔽',
            subTitle: '屏蔽标题、简介或标签中包含指定内容的视频',
            setKey: SettingBoxKey.enableKeywordFilter,
            defaultVal: false,
          ),
          ListTile(
            onTap: () => Get.toNamed('/keywordBlockSetting'),
            dense: false,
            title: Text('关键词屏蔽设置', style: titleStyle),
            subtitle: Text(
              '视频推荐、热门、排行榜、搜索；评论、置顶评论、楼中楼和嵌套回复；\n'
              '开启下方开关后额外过滤关注动态和UP主页的视频、动态\n'
              '原样关键词 ${KeywordSettings.literal.length} 个，正则 ${KeywordSettings.regex.length} 个',
              style: subTitleStyle,
            ),
          ),
          const SetSwitchItem(
            title: '屏蔽关注UP的关键词内容',
            subTitle: '过滤关注动态及UP主页中标题、简介或正文含屏蔽词的视频和动态',
            setKey: SettingBoxKey.enableKeywordFilterForFollowed,
            defaultVal: false,
          ),
          ListTile(
            onTap: () {
              if (!userLogin) {
                SmartDialog.showToast('请先登录');
              }
              MemberHttp.cookieToKey();
            },
            dense: false,
            title: Text('刷新access_key', style: titleStyle),
          ),
        ],
      ),
    );
  }
}
