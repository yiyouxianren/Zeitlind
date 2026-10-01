import 'package:bottom_sheet/bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/models/follow/result.dart';
import 'package:pilipala/pages/follow/index.dart';
import 'package:pilipala/pages/video/detail/introduction/widgets/group_panel.dart';
import 'package:pilipala/utils/feed_back.dart';
import 'package:pilipala/utils/utils.dart';

class FollowItem extends StatelessWidget {
  final FollowItemModel item;
  final FollowController? ctr;

  /// 该条目所属的分组列表：分组 tab 下是分组内 up 列表；
  /// 为 null 时回退到 ctr.followList（"全部关注"视图）。
  /// 用于批量取关的"全选当前分组"与昵称匹配。
  final List<FollowItemModel>? list;
  const FollowItem({super.key, required this.item, this.ctr, this.list});

  @override
  Widget build(BuildContext context) {
    String heroTag = Utils.makeHeroTag(item.mid);
    // 批量模式下勾选状态必须响应式：obx 包裹后勾选/取消会立即刷新勾选框，
    // 否则 Obx 外读取的 batchMode 是普通布尔快照，多选 UI 不更新
    if (ctr != null) {
      return Obx(() => _buildItem(context, heroTag));
    }
    return _buildItem(context, heroTag);
  }

  Widget _buildItem(BuildContext context, String heroTag) {
    final bool batchMode = ctr?.batchMode.value ?? false;
    return ListTile(
      onTap: () {
        if (batchMode && ctr != null) {
          _toggleSelect(ctr!);
          return;
        }
        feedBack();
        Get.toNamed('/member?mid=${item.mid}',
            arguments: {'face': item.face, 'heroTag': heroTag});
      },
      leading: Hero(
        tag: heroTag,
        child: NetworkImgLayer(
          width: 45,
          height: 45,
          type: 'avatar',
          src: item.face,
        ),
      ),
      title: Text(
        item.uname!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        item.sign!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      dense: true,
      trailing: batchMode
          ? Checkbox(
              value: ctr!.selectedMids.contains(item.mid),
              onChanged: (_) => _toggleSelect(ctr!),
            )
          : ctr != null && ctr!.isOwner.value
          ? SizedBox(
              height: 34,
              child: TextButton(
                onPressed: () async {
                  await showFlexibleBottomSheet(
                    bottomSheetBorderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    minHeight: 1,
                    initHeight: 1,
                    maxHeight: 1,
                    context: Get.context!,
                    builder: (BuildContext context,
                        ScrollController scrollController, double offset) {
                      return GroupPanel(
                        mid: item.mid!,
                        scrollController: scrollController,
                      );
                    },
                    anchors: [1],
                    isSafeArea: true,
                  );
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
                  foregroundColor: Theme.of(context).colorScheme.outline,
                  backgroundColor:
                      Theme.of(context).colorScheme.onInverseSurface, // 设置按钮背景色
                ),
                child: const Text(
                  '已关注',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            )
          : const SizedBox(),
    );
  }

  /// 该条目所属分组内 mid -> uname 映射（批量取关存档用）。
  /// 分组 tab 下 FollowController.followList 是空的，必须用分组自己的列表。
  Map<int, String> get nameMap {
    final List<FollowItemModel> src = list ?? ctr?.followList ?? [];
    final Map<int, String> map = {};
    for (final e in src) {
      if (e.mid != null) map[e.mid!] = e.uname ?? '';
    }
    return map;
  }

  void _toggleSelect(FollowController ctr) {
    if (ctr.selectedMids.remove(item.mid)) {
      return;
    }
    ctr.selectedMids.add(item.mid!);
  }
}
