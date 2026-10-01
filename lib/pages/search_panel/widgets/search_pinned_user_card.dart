import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/models/search/result.dart';
import 'package:pilipala/utils/utils.dart';

/// 搜索结果页置顶的 UP 主卡片：出现在视频结果之前，
/// 与网页端"搜索推荐 UP 主"一致。
class SearchPinnedUserCard extends StatelessWidget {
  const SearchPinnedUserCard({required this.item, super.key});

  final SearchUserItemModel item;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
        fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
        color: Theme.of(context).colorScheme.outline);
    final String heroTag = Utils.makeHeroTag(item.mid);

    return InkWell(
      onTap: () => Get.toNamed('/member?mid=${item.mid}',
          arguments: {'heroTag': heroTag, 'face': item.upic}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Row(
          children: [
            Hero(
              tag: heroTag,
              child: NetworkImgLayer(
                width: 42,
                height: 42,
                src: item.upic,
                type: 'avatar',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          item.uname ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (item.level != null && item.level! > 0)
                        Image.asset(
                          'assets/images/lv/lv${item.level}.png',
                          height: 11,
                        ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(4)),
                        ),
                        child: Text('UP 主', style: style),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '粉丝：${item.fans ?? '-'} · 视频：${item.videos ?? '-'}',
                          style: style,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if ((item.usign ?? '').isNotEmpty)
                    Text(
                      item.usign!,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: Theme.of(context).colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
