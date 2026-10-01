import 'package:flutter/material.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';

/// @用户联想面板：展示搜索结果列表，点击选择用户
class MentionPanel extends StatelessWidget {
  const MentionPanel({
    super.key,
    required this.results,
    required this.onChoose,
    this.keyword = '',
  });

  final List<Map> results;
  final Function(Map user) onChoose;
  final String keyword;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            keyword.isEmpty ? '输入@后搜索用户' : '未找到"$keyword"相关用户',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final Map user = results[index];
        final String name = (user['name'] ?? '').toString();
        final String face = (user['face'] ?? '').toString();
        final int fans = int.tryParse('${user['fans']}') ?? 0;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: face.isNotEmpty
              ? NetworkImgLayer(
                  width: 38,
                  height: 38,
                  type: 'avatar',
                  src: face,
                )
              : const CircleAvatar(radius: 19),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: fans > 0
              ? Text(
                  '粉丝：$fans',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                )
              : null,
          onTap: () => onChoose(user),
        );
      },
    );
  }
}
