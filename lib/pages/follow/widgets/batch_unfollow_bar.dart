import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/pages/follow/index.dart';
import 'package:pilipala/utils/unfollow_service.dart';

/// 批量取关底部操作栏（两行布局）：
/// 第一行：名单状态 + 清空名单 + 退出多选
/// 第二行：全选 / 加入名单 / 开始·暂停
class BatchUnfollowBar extends StatelessWidget {
  final FollowController ctr;
  const BatchUnfollowBar({super.key, required this.ctr});

  @override
  Widget build(BuildContext context) {
    final UnfollowService svc = UnfollowService.instance;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已选 ${ctr.selectedMids.length} · 待移除 ${svc.pendingList.length}'
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
                    ctr.selectedMids.clear();
                  },
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      final List<int> visibleMids =
                          ctr.activeGroupList.map((e) => e.mid!).toList();
                      if (visibleMids.isNotEmpty &&
                          ctr.selectedMids.length == visibleMids.length &&
                          ctr.selectedMids.toSet().containsAll(visibleMids)) {
                        ctr.selectedMids.clear();
                      } else {
                        ctr.selectedMids.value = visibleMids;
                      }
                    },
                    icon: const Icon(Icons.select_all_outlined, size: 20),
                    label: Text(
                      ctr.activeGroupList.isNotEmpty &&
                              ctr.selectedMids.length ==
                                  ctr.activeGroupList.length &&
                              ctr.selectedMids
                                  .toSet()
                                  .containsAll(ctr.activeGroupList
                                      .map((e) => e.mid!)
                                      .toList())
                          ? '取消全选'
                          : '全选',
                    ),
                  ),
                ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ctr.selectedMids.isEmpty
                        ? null
                        : () {
                            final Map<int, String> nameMap =
                                ctr.knownUserNameMap();
                            final Map<int, String> groupMap =
                                ctr.knownGroupUserNameMap();
                            final items = ctr.selectedMids
                                .map((mid) => <String, dynamic>{
                                      'mid': mid,
                                      'uname': nameMap[mid] ??
                                          groupMap[mid] ??
                                          '',
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
