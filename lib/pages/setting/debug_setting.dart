import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../utils/debug_bridge.dart';
import '../../utils/storage.dart';

/// 调试模式设置页：仅 debug 构建可进入（release 构建路由不注册）。
///
/// - 总开关：控制所有 ADB 注入命令是否生效（PING 探活除外）
/// - 使用说明：与 adb_injecting.md 内容一致的展示
class DebugSettingPage extends StatefulWidget {
  const DebugSettingPage({super.key});

  @override
  State<DebugSettingPage> createState() => _DebugSettingState();
}

class _DebugSettingState extends State<DebugSettingPage> {
  Box setting = GStrorage.setting;
  late bool adbInjectEnabled;

  @override
  void initState() {
    super.initState();
    adbInjectEnabled =
        setting.get(DebugBridge.kAdbInjectEnabled, defaultValue: false) == true;
  }

  Future<void> _toggle(bool value) async {
    await setting.put(DebugBridge.kAdbInjectEnabled, value);
    setState(() => adbInjectEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle = Theme.of(context).textTheme.titleMedium!;
    final TextStyle subTitleStyle = Theme.of(context)
        .textTheme
        .labelMedium!
        .copyWith(color: Theme.of(context).colorScheme.outline);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text('调试模式', style: titleStyle),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('ADB 注入', style: titleStyle),
            subtitle: Text(
              '开启后允许通过 adb broadcast 调试命令（跳转、读取数据等）注入应用；'
              '仅 debug 构建可用，正式版始终关闭',
              style: subTitleStyle,
            ),
            value: adbInjectEnabled,
            onChanged: _toggle,
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('使用说明', style: titleStyle),
            subtitle: Text(
              '与 E:\\BILIGAI\\adb_injecting.md 内容一致，可在电脑端查看完整文档',
              style: subTitleStyle,
            ),
          ),
          ...debugGuideSections(context, titleStyle, subTitleStyle),
        ],
      ),
    );
  }

  /// 与 adb_injecting.md 保持一致的使用说明内容。
  List<Widget> debugGuideSections(
      BuildContext context, TextStyle titleStyle, TextStyle subTitleStyle) {
    return const [
      _GuideSection(
        heading: '协议总览',
        body: '所有命令通过 Android broadcast 发出：\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_<命令> '
            '[--ei 键 整数] [--es 键 字符串] [--ez 键 布尔]\n\n'
            '响应统一以 ADB_RSP 前缀写入 logcat（tag=flutter）：\n'
            'adb logcat -s flutter | grep ADB_RSP\n\n'
            '安全性：release 构建接收器不注册；debug 构建需先打开本页的「ADB 注入」开关（PING 探活除外）。',
      ),
      _GuideSection(
        heading: 'PING 探活',
        body: 'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_PING\n\n'
            '无需开关。返回可用命令列表，用于确认链路与版本。',
      ),
      _GuideSection(
        heading: '读取/设置音频模式',
        body:
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_AUDIO_MODE\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_SET_AUDIO_MODE --ei enable 1\n\n'
            'enable：1 开启音频模式 / 0 关闭。设置后进入直播间即为纯音频播放。',
      ),
      _GuideSection(
        heading: '跳转直播间',
        body:
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GOTO_LIVE_ROOM --ei roomId <房间号>\n\n'
            '⚠️ 示例房间号仅演示格式，直播间会下播；请先通过 B 站网页端或开放接口\n'
            '（room/v1/Room/get_info 的 live_status==1）确认当前在播房间号再注入。\n'
            '导航后可用 GET_CURRENT_STATE 校验标题/主播。',
      ),
      _GuideSection(
        heading: '跳转视频（BV 号）',
        body:
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GOTO_VIDEO --es bvid <BV号>\n\n'
            '⚠️ 示例 BV 号仅演示格式（编号部分大小写敏感）；请先通过热门/搜索接口\n'
            '（x/web-interface/popular 的 data.list[].bvid）获取当前有效 BV 号再注入。',
      ),
      _GuideSection(
        heading: '读取评论',
        body: '按 BV 号拉取：\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_COMMENTS '
            '--es bvid BV1GJ411x7h7 --ei page 1 --ei count 20\n\n'
            '在直播间内调用（返回实时弹幕消息列表）：\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_COMMENTS --ei count 20\n\n'
            'page 默认 1，count 默认 20。',
      ),
      _GuideSection(
        heading: '读取视频弹幕',
        body: '按 cid 拉取指定分段（cid 超过 2147483647 必须用 --el 而非 --ei）：\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_DANMAKU '
            '--el cid 42164027811 --ei segment 1 --ei count 30\n\n'
            '处于视频页时可不传 cid（自动取当前视频）。segment 从 1 开始，每段 6 分钟；count 默认 30。',
      ),
      _GuideSection(
        heading: '读取直播间弹幕',
        body:
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_LIVE_DANMAKU --ei count 30\n\n'
            '需先进入直播间；返回当前内存中的实时弹幕消息。',
      ),
      _GuideSection(
        heading: '读取当前页面状态',
        body:
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_CURRENT_STATE\n\n'
            '返回当前所处页面（video / liveRoom / search / article / dynamic / home 等）'
            '及上下文：视频页返回 bvid/cid，直播间返回 roomId/标题/主播/开播状态，'
            '搜索页返回关键词，专栏返回 id/标题/类型。\n\n'
            '视频/直播页额外返回分辨率与方向：videoWidth/videoHeight/resolution'
            '（如 1920x1080，音频模式为 null）、videoOrientation（landscape/portrait）；'
            '直播间另有 streamOrientation（服务端标记的竖屏/横屏直播）。',
      ),
      _GuideSection(
        heading: '读取当前页面控件（语义树）',
        body: 'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_UI_TREE\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_UI_TREE --es contains 下载\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_GET_UI_TREE --ez actionsOnly false\n\n'
            'Flutter 控件大多不暴露给 uiautomator，此命令直接读取语义树，返回已加载'
            '控件的中心坐标（x/y）+ 文本（label）+ 动作（actions），'
            '可直接用 input tap <x> <y> 点击。\n\n'
            '注意：坐标随屏幕状态变化，列表滚动后需重查；播放器控制条自动隐藏后'
            '其按钮不在树中，先点播放器中央唤出再查；部分 Tab/文本节点无 tap 动作，'
            '查文本时加 --ez actionsOnly false。',
      ),
      _GuideSection(
        heading: '直接触发控件（推荐）',
        body: 'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_TAP_NODE --es label 下载视频\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_TAP_NODE --ei id 12345\n'
            'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_TAP_NODE --es label 某文本 --es action longPress\n\n'
            '直接调用语义树的动作处理器（等价无障碍点击），不受遮挡层/坐标漂移影响，'
            '比 input tap 坐标模拟可靠。label 为 contains 匹配，id 取自 GET_UI_TREE。'
            '响应回显命中的 id/label/action。\n\n'
            '限制：裸 IconButton/自定义按钮通常只有动作没有文本，这类用 --ei id 或退化为坐标点击。',
      ),
      _GuideSection(
        heading: '强制显示播放器控制条',
        body: 'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_SHOW_CONTROLS --ei seconds 25\n\n'
            '控制条隐藏时其按钮不在语义树中。此命令显示控制条并取消自动隐藏，'
            '期间立即 GET_UI_TREE 枚举 / TAP_NODE 派发。\n\n'
            '注意：控制条内的自定义按钮（播放/全屏/倍速）本身不注册语义节点，'
            '可见后也不会出现在 GET_UI_TREE（只有播放器手势区一个大节点带 tap/longPress）；'
            '这类按钮仍需坐标 input tap。操作行（点赞/投币/收藏/分享/稍后看）、'
            'Tab、列表项、bottom sheet 选项都有完整语义可直接 TAP_NODE。',
      ),
      _GuideSection(
        heading: '直接设置播放倍速',
        body: 'adb shell am broadcast -a com.Zeitlind.bill.DEBUG_SET_PLAYBACK_SPEED --es speed 2.0\n\n'
            '直接调用播放器 setPlaybackSpeed，无需打开倍速弹窗；任何播放页可用。\n\n'
            '注意：Android 12 部分ROM的 am broadcast 不支持 --ed（double），'
            '小数参数统一用 --es 字符串传递。',
      ),
      _GuideSection(
        heading: '扩展新命令',
        body: 'Dart 侧 DebugBridge._registerDefaults() 中注册 <命令>: 处理器 即可；'
            'native 侧显式 action 列表同步加一项同名命令。',
      ),
    ];
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(body,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
