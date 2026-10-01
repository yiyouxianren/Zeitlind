import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controller.dart';

/// 离线缓存页：列出已下载的视频（Download/Zeitlind/Video）与音频。
/// 点击视频卡片进入本地播放页。
class OfflineCachePage extends StatefulWidget {
  const OfflineCachePage({super.key});

  @override
  State<OfflineCachePage> createState() => _OfflineCachePageState();
}

class _OfflineCachePageState extends State<OfflineCachePage> {
  late OfflineCacheController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(OfflineCacheController());
  }

  @override
  void dispose() {
    Get.delete<OfflineCacheController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Obx(() => controller.batchMode.value
            ? Text('已选 ${controller.selectedPaths.length} 项',
                style: Theme.of(context).textTheme.titleMedium)
            : Text('离线缓存', style: Theme.of(context).textTheme.titleMedium)),
        actions: [
          Obx(
            () => !controller.batchMode.value &&
                    (controller.videoList.isNotEmpty ||
                        controller.musicList.isNotEmpty)
                ? IconButton(
                    tooltip: '批量删除',
                    icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                    onPressed: () => controller.batchMode.value = true,
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: '导入文件',
            onPressed: () => controller.importFromFile(),
            icon: const Icon(Icons.add_to_drive_outlined),
          ),
          IconButton(
            onPressed: () => controller.refreshList(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMsg.value.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(controller.errorMsg.value),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => controller.refreshList(),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        if (controller.videoList.isEmpty && controller.musicList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('暂无离线内容\n在视频播放页右上角下载后会保存在这里',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => controller.importFromFile(),
                  icon: const Icon(Icons.add_to_drive_outlined, size: 20),
                  label: const Text('导入已有视频文件'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => controller.refreshList(),
          child: ListView(
            children: [
              if (controller.videoList.isNotEmpty) ...[
                _sectionHeader('视频 · ${controller.videoList.length}'),
                ...controller.videoList.map(_videoTile),
              ],
              if (controller.musicList.isNotEmpty) ...[
                _sectionHeader('音频 · ${controller.musicList.length}'),
                ...controller.musicList.map(_musicTile),
              ],
            ],
          ),
        );
      }),
      bottomNavigationBar: Obx(
        () => controller.batchMode.value
            ? _batchDeleteBar()
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _batchDeleteBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(0.15)),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () {
              final all = [...controller.videoList, ...controller.musicList]
                  .map((e) => e.path)
                  .toSet();
              if (controller.selectedPaths.length == all.length) {
                controller.selectedPaths.clear();
              } else {
                controller.selectedPaths.assignAll(all);
              }
            },
            icon: const Icon(Icons.select_all_outlined, size: 20),
            label: const Text('全选'),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: Text(
              '已选 ${controller.selectedPaths.length} / '
              '${controller.videoList.length + controller.musicList.length}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: controller.selectedPaths.isEmpty
                ? null
                : () => _confirmDelete(),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text('删除 ${controller.selectedPaths.length} 项'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              controller.batchMode.value = false;
              controller.selectedPaths.clear();
            },
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final int n = controller.selectedPaths.length;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('将删除选中的 $n 项内容。\n'
            '删除视频时会同时删除对应的弹幕与分段信息；删除音频仅删除音频文件。'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Get.back(result: true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteSelected();
    }
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _videoTile(OfflineVideoItem item) {
    final bool batch = controller.batchMode.value;
    return ListTile(
      leading: batch
          ? Checkbox(
              value: controller.selectedPaths.contains(item.path),
              onChanged: (_) => controller.toggleSelect(item.path),
            )
          : Container(
              width: 64,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.movie_outlined,
                  color: Theme.of(context).colorScheme.primary),
            ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.sizeLabel} · ${_fmtDate(item.modified)}',
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).colorScheme.outline),
      ),
      onTap: () {
        if (controller.batchMode.value) {
          controller.toggleSelect(item.path);
          return;
        }
        Get.toNamed(
          '/offlinePlayer',
          arguments: <String, dynamic>{
            'item': item,
            'all': controller.videoList.toList(),
          },
        );
      },
    );
  }

  Widget _musicTile(OfflineVideoItem item) {
    final bool batch = controller.batchMode.value;
    return ListTile(
      leading: batch
          ? Checkbox(
              value: controller.selectedPaths.contains(item.path),
              onChanged: (_) => controller.toggleSelect(item.path),
            )
          : Icon(Icons.music_note_outlined,
              color: Theme.of(context).colorScheme.primary),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.sizeLabel} · ${_fmtDate(item.modified)}',
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).colorScheme.outline),
      ),
      onTap: () {
        if (controller.batchMode.value) {
          controller.toggleSelect(item.path);
          return;
        }
        // 进入离线音频播放页（音频模式控件）
        Get.toNamed(
          '/offlineAudio',
          arguments: <String, dynamic>{
            'item': item,
            'all': controller.musicList.toList(),
          },
        );
      },
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
