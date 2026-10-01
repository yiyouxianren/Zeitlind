import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/utils/download_logger.dart';
import 'package:pilipala/utils/id_utils.dart';
import 'package:pilipala/utils/batch_download_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/common/video_episode_type.dart';

class EpisodeBottomSheet {
  final List<dynamic> episodes;
  final int currentCid;
  final dynamic dataType;
  final BuildContext context;
  final Function changeFucCall;
  final int? cid;
  final double? sheetHeight;
  bool isFullScreen = false;

  /// 合集面板启用批量下载：条目出现勾选框，标题栏出现批量下载入口
  final bool enableBatchDownload;

  /// 多选模式状态（仅在 enableBatchDownload 时使用）
  final Set<int> _selected = <int>{};
  bool _batchMode = false;
  bool _downloading = false;

  EpisodeBottomSheet({
    required this.episodes,
    required this.currentCid,
    required this.dataType,
    required this.context,
    required this.changeFucCall,
    this.cid,
    this.sheetHeight,
    this.isFullScreen = false,
    this.enableBatchDownload = false,
  });

  Widget buildEpisodeListItem(
    dynamic episode,
    int index,
    bool isCurrentIndex, {
    StateSetter? setState,
  }) {
    Color primary = Theme.of(context).colorScheme.primary;
    Color onSurface = Theme.of(context).colorScheme.onSurface;

    String title = '';
    switch (dataType) {
      case VideoEpidoesType.videoEpisode:
        title = episode.title;
        break;
      case VideoEpidoesType.videoPart:
        title = episode.pagePart;
        break;
      case VideoEpidoesType.bangumiEpisode:
        title = '第${episode.title}话  ${episode.longTitle!}';
        break;
    }

    // 批量模式：条目尾部加勾选框，点击行切换勾选
    final Widget? trailingCheckbox = (_batchMode && setState != null)
        ? Checkbox(
            value: _selected.contains(index),
            onChanged: (_) =>
                _toggleSelect(setState, index),
          )
        : null;

    return isFullScreen || episode?.cover == null || episode?.cover == ''
        ? ListTile(
            onTap: () {
              if (_batchMode && setState != null) {
                _toggleSelect(setState, index);
                return;
              }
              SmartDialog.showToast('切换至「$title」');
              changeFucCall.call(episode, index);
            },
            dense: false,
            leading: isCurrentIndex
                ? Image.asset(
                    'assets/images/live.gif',
                    color: primary,
                    height: 12,
                  )
                : null,
            title: Text(title,
                style: TextStyle(
                  fontSize: 14,
                  color: isCurrentIndex ? primary : onSurface,
                )),
            trailing: trailingCheckbox)
        : InkWell(
            onTap: () {
              if (_batchMode && setState != null) {
                _toggleSelect(setState, index);
                return;
              }
              SmartDialog.showToast('切换至「$title」');
              changeFucCall.call(episode, index);
            },
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 14, right: 14, top: 8, bottom: 8),
              child: Row(
                children: [
                  NetworkImgLayer(
                      width: 130, height: 75, src: episode?.cover ?? ''),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 14,
                        color: isCurrentIndex ? primary : onSurface,
                      ),
                    ),
                  ),
                  if (trailingCheckbox != null) ...[
                    const SizedBox(width: 6),
                    trailingCheckbox,
                  ],
                ],
              ),
            ),
          );
  }

  void _toggleSelect(StateSetter setState, int index) {
    if (!_selected.remove(index)) {
      _selected.add(index);
    }
    setState(() {});
  }

  Widget buildTitle({StateSetter? setState}) {
    final bool batchMode = _batchMode;
    return AppBar(
      toolbarHeight: 45,
      automaticallyImplyLeading: false,
      centerTitle: false,
      title: batchMode && setState != null
          ? TextButton(
              onPressed: _downloading
                  ? null
                  : () {
                      if (_selected.length == episodes.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(
                            List<int>.generate(episodes.length, (i) => i));
                      }
                      setState(() {});
                    },
              child: Text(
                '已选 ${_selected.length}/${episodes.length} · ${_selected.length == episodes.length ? '取消全选' : '全选'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          : Text(
              '合集（${episodes.length}）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
      actions: !isFullScreen
          ? [
              if (enableBatchDownload && setState != null) ...[
                if (batchMode) ...[
                  // 下载操作固定在 AppBar（不受列表布局影响）
                  FilledButton.tonalIcon(
                    onPressed: (_selected.isEmpty || _downloading)
                        ? null
                        : () => _startBatchDownload(setState),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(_downloading ? '下载中' : '下载(${_selected.length})'),
                  ),
                  TextButton(
                    onPressed: _downloading
                        ? null
                        : () {
                            _selected.clear();
                            setState(() => _batchMode = false);
                          },
                    child: const Text('取消'),
                  ),
                ]
                else
                  // 顶端批量下载入口：文字+图标，点击目标大且直观
                  TextButton.icon(
                    onPressed: () {
                      _selected.clear();
                      setState(() => _batchMode = true);
                    },
                    icon: const Icon(Icons.download_outlined, size: 20),
                    label: const Text('批量下载'),
                  ).wrapSemantics('批量下载入口'),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 14),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 14),
              ],
            ]
          : null,
    );
  }

  /// 将勾选的视频加入批量下载服务队列（顺序按合集中的顺序），随后退出多选。
  /// 下载进度与「后台下载」由 BatchDownloadService 的弹窗承载。
  void _startBatchDownload(StateSetter setState) {
    DownloadLogger.log('[batch] sheet confirm, selected=${_selected.length}');
    if (_downloading || _selected.isEmpty) return;
    final List<int> sorted = _selected.toList()..sort();
    final List<Map<String, dynamic>> items = [];
    for (final index in sorted) {
      final dynamic episode = episodes[index];
      final int? aid = episode.aid;
      final int? cidVal = episode.cid;
      if (aid == null || cidVal == null) continue;
      items.add({
        'bvid': episode.bvid ?? IdUtils.av2bv(aid),
        'cid': cidVal,
        'title': episode.title ?? '未命名',
      });
    }
    if (items.isEmpty) return;
    DownloadLogger.log('[batch] enqueue ${items.length} items');

    _downloading = true;
    try {
      BatchDownloadService.instance.enqueue(items);
      // 交由服务后退出多选模式
      _selected.clear();
      _batchMode = false;
      setState(() {});
    } finally {
      _downloading = false;
    }
  }

  Widget buildShowContent(BuildContext context) {
    final ItemScrollController itemScrollController = ItemScrollController();
    int currentIndex = episodes.indexWhere((dynamic e) => e.cid == currentCid);
    // 初始定位只执行一次：面板打开时滚到当前集。
    // 之后 setState（勾选/全选等）重建时不再 jumpTo，否则列表会跳回初始位置。
    bool initialJumpDone = false;
    return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
      if (!initialJumpDone) {
        initialJumpDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          itemScrollController.jumpTo(index: currentIndex);
        });
      }
      final double panelHeight = sheetHeight ?? 0;
      return SizedBox(
        height: panelHeight,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              buildTitle(setState: setState),
              Expanded(
                child: Material(
                  child: PageStorage(
                    bucket: PageStorageBucket(),
                    child: ScrollablePositionedList.builder(
                      itemScrollController: itemScrollController,
                      itemCount: episodes.length + 1,
                      itemBuilder: (BuildContext context, int index) {
                        bool isLastItem = index == episodes.length;
                        bool isCurrentIndex = currentIndex == index;
                        return isLastItem
                            ? SizedBox(
                                height: MediaQuery.of(context).padding.bottom + 20,
                              )
                            : buildEpisodeListItem(
                                episodes[index],
                                index,
                                isCurrentIndex,
                                setState: setState,
                              );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// The [BuildContext] of the widget that calls the bottom sheet.
  PersistentBottomSheetController show(BuildContext context) {
    final PersistentBottomSheetController btmSheetCtr = showBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return buildShowContent(context);
      },
    );
    return btmSheetCtr;
  }
}

/// 语义包装：给无文本的控件挂 label，供无障碍与 ADB 调试桥 TAP_NODE 派发
extension SemanticsWrap on Widget {
  Widget wrapSemantics(String label) => Semantics(
        label: label,
        button: true,
        child: this,
      );
}
