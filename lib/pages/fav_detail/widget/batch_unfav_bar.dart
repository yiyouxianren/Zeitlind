import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/pages/fav_detail/controller.dart';
import 'package:pilipala/utils/id_utils.dart';
import 'package:pilipala/utils/unfav_service.dart';

/// 批量移除收藏底部操作栏（两行布局，与批量取关一致）：
/// 第一行：名单状态 + 清空名单 + 退出多选
/// 第二行：全选 / 加入名单 / 开始·暂停
class BatchUnfavBar extends StatelessWidget {
  final FavDetailController ctr;
  const BatchUnfavBar({super.key, required this.ctr});

  @override
  Widget build(BuildContext context) {
    final UnfavService svc = UnfavService.instance;
    return Obx(
      () => Container(
        padding: EdgeInsets.fromLTRB(
            8, 6, 8, 6 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.15)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- 第一行：名单状态与全局操作 ----
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已选 ${ctr.selectedAids.length} · '
                    '待移除 ${svc.pendingList.length}'
                    '${svc.running.value ? "（进行中）" : ""}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: svc.pendingList.isEmpty || svc.running.value
                      ? null
                      : () {
                          svc.clearPending();
                          SmartDialog.showToast('已清空待移除名单');
                        },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空名单'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  tooltip: '退出多选',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    ctr.batchMode.value = false;
                    ctr.selectedAids.clear();
                  },
                ),
              ],
            ),
            // ---- 第二行：选择与执行 ----
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      if (ctr.selectedAids.length == ctr.favList.length &&
                          ctr.favList.isNotEmpty) {
                        ctr.selectedAids.clear();
                      } else {
                        ctr.selectedAids.value =
                            ctr.favList.map((e) => e.id!).toList();
                      }
                    },
                    icon: const Icon(Icons.select_all_outlined, size: 20),
                    label: Text(
                      ctr.favList.isNotEmpty &&
                              ctr.selectedAids.length == ctr.favList.length
                          ? '取消全选'
                          : '全选',
                    ),
                  ),
                ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ctr.selectedAids.isEmpty
                        ? null
                        : () {
                            final mediaId = ctr.mediaId!;
                            final items = ctr.favList
                                .where((e) => ctr.selectedAids.contains(e.id))
                                .map((e) => <String, dynamic>{
                                      'aid': e.id!,
                                      'bvid': e.bvid ?? IdUtils.av2bv(e.id!),
                                      'title': e.title ?? '',
                                      'mediaId': mediaId,
                                    })
                                .toList();
                            svc.addPending(items);
                            SmartDialog.showToast('已加入名单：+${items.length}');
                          },
                    icon: const Icon(Icons.playlist_add_check_outlined,
                        size: 18),
                    label: const Text('加入名单'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: svc.running.value
                      ? FilledButton.tonalIcon(
                          onPressed: () => svc.stop(),
                          icon: const Icon(Icons.pause_circle_outline,
                              size: 18),
                          label: const Text('暂停'),
                        )
                      : FilledButton.icon(
                          onPressed: svc.pendingList.isEmpty
                              ? null
                              : () => svc.start(),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('开始'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
