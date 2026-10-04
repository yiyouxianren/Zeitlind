import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/pages/fav_detail/controller.dart';

/// 批量移除收藏底部操作栏（官方 batch-del 接口，单次请求完成）：
/// 第一行：已选计数 + 退出多选
/// 第二行：全选 / 移除所选
class BatchUnfavBar extends StatelessWidget {
  final FavDetailController ctr;
  const BatchUnfavBar({super.key, required this.ctr});

  Future<void> _confirmRemove(BuildContext context) async {
    SmartDialog.show(
      useSystem: true,
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('提示'),
          content: Text('确定移除选中的 ${ctr.selectedAids.length} 个视频吗？'),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(),
              child: Text(
                '点错了',
                style: TextStyle(color: Theme.of(ctx).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () async {
                SmartDialog.dismiss();
                await ctr.removeSelected();
              },
              child: const Text('确认移除'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
            // ---- 第一行：已选计数与退出多选 ----
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已选 ${ctr.selectedAids.length} 个视频',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            // ---- 第二行：全选 / 移除所选 ----
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
                    label: Obx(
                      () => Text(
                        ctr.favList.isNotEmpty &&
                                ctr.selectedAids.length == ctr.favList.length
                            ? '取消全选'
                            : '全选',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ctr.selectedAids.isEmpty ||
                            ctr.batchRemoving.value
                        ? null
                        : () => _confirmRemove(context),
                    icon: ctr.batchRemoving.value
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline, size: 18),
                    label: Text('移除所选 (${ctr.selectedAids.length})'),
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
