import 'package:flutter/material.dart';
import 'package:pilipala/pages/setting/widgets/switch_item.dart';
import 'package:pilipala/utils/storage.dart';

class LiveSetting extends StatefulWidget {
  const LiveSetting({super.key});

  @override
  State<LiveSetting> createState() => _LiveSettingState();
}

class _LiveSettingState extends State<LiveSetting> {
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
        title: Text('直播设置', style: Theme.of(context).textTheme.titleMedium),
      ),
      body: ListView(
        children: [
          const SetSwitchItem(
            title: '自动佩戴粉丝牌',
            subTitle: '进入直播间时，若粉丝牌库中有该主播的粉丝牌则自动佩戴，'
                '离开后恢复原先佩戴状态；未命中则不佩戴',
            setKey: SettingBoxKey.autoWearFansMedal,
            defaultVal: true,
          ),
          ListTile(
            dense: false,
            title: Text('说明', style: titleStyle),
            subtitle: Text(
              '佩戴行为通过 B 站官方接口生效，与其他客户端的佩戴状态互通；'
              '需登录账号',
              style: subTitleStyle,
            ),
          ),
        ],
      ),
    );
  }
}
