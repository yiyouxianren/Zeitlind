import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:pilipala/utils/unfav_service.dart';

/// 批量移除收藏规则设置
class UnfavSettingPage extends StatefulWidget {
  const UnfavSettingPage({super.key});

  @override
  State<UnfavSettingPage> createState() => _UnfavSettingPageState();
}

class _UnfavSettingPageState extends State<UnfavSettingPage> {
  final Box setting = GStrorage.setting;

  late int ruleType; // 0 等长 1 间歇 2 随机
  late int intervalSec;
  late int batchCount;
  late int restSec;
  late int baseSec;
  late int randMaxSec;

  @override
  void initState() {
    super.initState();
    ruleType = setting.get(SettingBoxKey.unfavRuleType, defaultValue: 0);
    intervalSec =
        setting.get(SettingBoxKey.unfavIntervalSec, defaultValue: 60);
    batchCount =
        setting.get(SettingBoxKey.unfavBatchCount, defaultValue: 5);
    restSec = setting.get(SettingBoxKey.unfavRestSec, defaultValue: 300);
    baseSec = setting.get(SettingBoxKey.unfavBaseSec, defaultValue: 60);
    randMaxSec =
        setting.get(SettingBoxKey.unfavRandMaxSec, defaultValue: 20);
  }

  Future<void> _save() async {
    await setting.put(SettingBoxKey.unfavRuleType, ruleType);
    await setting.put(SettingBoxKey.unfavIntervalSec, intervalSec);
    await setting.put(SettingBoxKey.unfavBatchCount, batchCount);
    await setting.put(SettingBoxKey.unfavRestSec, restSec);
    await setting.put(SettingBoxKey.unfavBaseSec, baseSec);
    await setting.put(SettingBoxKey.unfavRandMaxSec, randMaxSec);
  }

  Widget _numField({
    required String label,
    required int value,
    required Function(int) onChanged,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(label)),
          Expanded(
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              controller: TextEditingController(text: '$value')
                ..selection = TextSelection.collapsed(offset: '$value'.length),
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                final n = int.tryParse(v) ?? 0;
                onChanged(n);
                _save();
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text('批量移除收藏设置', style: Theme.of(context).textTheme.titleMedium),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text('移除规则',
              style: Theme.of(context).textTheme.titleMedium),
          RadioListTile<int>(
            value: 0,
            groupValue: ruleType,
            title: const Text('等长时间移除'),
            subtitle: const Text('每设置间隔移除一个'),
            onChanged: (v) => setState(() {
              ruleType = v!;
              _save();
            }),
          ),
          RadioListTile<int>(
            value: 1,
            groupValue: ruleType,
            title: const Text('间歇移除'),
            subtitle: const Text('等长时间移除 + 每移除N个休息一段时间'),
            onChanged: (v) => setState(() {
              ruleType = v!;
              _save();
            }),
          ),
          RadioListTile<int>(
            value: 2,
            groupValue: ruleType,
            title: const Text('随机时间移除'),
            subtitle: const Text('固定间隔 + 随机区间内的伪随机数'),
            onChanged: (v) => setState(() {
              ruleType = v!;
              _save();
            }),
          ),
          const Divider(),
          if (ruleType == 0) ...[
            _numField(
              label: '移除间隔（秒）',
              value: intervalSec,
              onChanged: (v) => intervalSec = v,
            ),
          ],
          if (ruleType == 1) ...[
            _numField(
              label: '移除间隔（秒）',
              value: intervalSec,
              onChanged: (v) => intervalSec = v,
            ),
            _numField(
              label: '每N个后休息',
              value: batchCount,
              onChanged: (v) => batchCount = v,
            ),
            _numField(
              label: '休息时长（秒）',
              value: restSec,
              onChanged: (v) => restSec = v,
            ),
          ],
          if (ruleType == 2) ...[
            _numField(
              label: '基础间隔（秒）',
              value: baseSec,
              onChanged: (v) => baseSec = v,
            ),
            _numField(
              label: '随机区间上界（秒）',
              value: randMaxSec,
              hint: '随机数范围 [0, 上界)',
              onChanged: (v) => randMaxSec = v,
            ),
          ],
          const Divider(),
          Text('说明',
              style: Theme.of(context).textTheme.titleMedium),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '· 名单移除仅在 APP 前台时执行\n'
              '· 已取消关注的 UP 会自动跳过（不报错）\n'
              '· 全部移除完成后会弹窗询问是否保存名单到\n'
              '  Download/Zeitlind/Unfollow/yyyy-mm-dd.txt\n'
              '· 随机规则示例：基础 60s + 上界 20s，'
              '即每次 60~79 秒后移除一个',
              style: TextStyle(height: 1.6),
            ),
          ),
          const Divider(),
          // 当前名单状态
          if (Get.isRegistered<UnfavService>()) ...[
            Obx(() {
              final svc = UnfavService.instance;
              return ListTile(
                dense: false,
                title: const Text('当前待移除名单'),
                subtitle: Text(
                  '${svc.pendingList.length} 个'
                  '${svc.running.value ? "（移除进行中，暂停后保留名单）" : ""}',
                ),
                trailing: svc.pendingList.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () {
                          svc.stop();
                          svc.clearPending();
                          setState(() {});
                        },
                        child: const Text('清空名单'),
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
