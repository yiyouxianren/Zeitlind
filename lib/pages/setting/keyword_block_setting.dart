import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/pages/setting/widgets/switch_item.dart';
import 'package:pilipala/utils/keyword_filter.dart';
import 'package:pilipala/utils/storage.dart';

class KeywordBlockSettingPage extends StatelessWidget {
  const KeywordBlockSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium!;
    final subtitleStyle = Theme.of(context).textTheme.labelMedium!.copyWith(
          color: Theme.of(context).colorScheme.outline,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('关键词屏蔽设置')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '生效范围：视频推荐、热门、排行榜、搜索，以及视频评论、置顶评论、楼中楼和嵌套回复。',
              ),
            ),
          ),
          ListTile(
            title: Text('原样关键词设置', style: titleStyle),
            subtitle: Text('屏蔽词：${KeywordSettings.literal.length}',
                style: subtitleStyle),
            onTap: () => Get.to(() => const KeywordListPage(literal: true)),
          ),
          ListTile(
            title: Text('正则屏蔽设置', style: titleStyle),
            subtitle: Text('正则：${KeywordSettings.regex.length}',
                style: subtitleStyle),
            onTap: () => Get.to(() => const KeywordListPage(literal: false)),
          ),
        ],
      ),
    );
  }
}

class KeywordListPage extends StatefulWidget {
  final bool literal;
  const KeywordListPage({required this.literal, super.key});

  @override
  State<KeywordListPage> createState() => _KeywordListPageState();
}

class _KeywordListPageState extends State<KeywordListPage> {
  late List<String> values;
  final inputController = TextEditingController();

  String get key => widget.literal
      ? SettingBoxKey.literalBlockKeywords
      : SettingBoxKey.regexBlockKeywords;

  @override
  void initState() {
    super.initState();
    values = List<String>.from(
        widget.literal ? KeywordSettings.literal : KeywordSettings.regex);
  }

  @override
  void dispose() {
    inputController.dispose();
    super.dispose();
  }

  Future<void> addValue() async {
    final value = inputController.text.trim();
    if (value.isEmpty) return;
    if (!widget.literal) {
      try {
        RegExp(value);
      } on FormatException {
        SmartDialog.showToast('正则表达式无效');
        return;
      }
    }
    if (!values.contains(value)) values.add(value);
    inputController.clear();
    await KeywordSettings.put(key, values);
    setState(() {});
  }

  Future<void> removeValue(String value) async {
    values.remove(value);
    await KeywordSettings.put(key, values);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.literal ? '原样关键词设置' : '正则屏蔽设置')),
      body: Column(
        children: [
          if (widget.literal)
            const SetSwitchItem(
              title: '屏蔽黑名单用户ID名',
              subTitle: '将黑名单用户的用户名作为原样关键词',
              setKey: SettingBoxKey.enableBlacklistNameKeyword,
              defaultVal: true,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: widget.literal ? '输入屏蔽关键词' : '输入正则表达式',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => addValue(),
                  ),
                ),
                IconButton(onPressed: addValue, icon: const Icon(Icons.add)),
              ],
            ),
          ),
          Expanded(
            child: values.isEmpty
                ? const Center(child: Text('暂无屏蔽词'))
                : ListView.builder(
                    itemCount: values.length,
                    itemBuilder: (_, index) => ListTile(
                      title: Text(values[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => removeValue(values[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
