import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/skeleton/video_card_h.dart';
import 'package:pilipala/common/widgets/no_data.dart';
import 'package:pilipala/pages/fav_detail/widget/fav_video_card.dart';

import 'controller.dart';

class FavSearchPage extends StatefulWidget {
  const FavSearchPage({super.key});

  @override
  State<FavSearchPage> createState() => _FavSearchPageState();
}

class _FavSearchPageState extends State<FavSearchPage> {
  final FavSearchController _favSearchCtr = Get.put(FavSearchController());
  late ScrollController scrollController;
  late int searchType;

  @override
  void initState() {
    super.initState();
    searchType = int.parse(Get.parameters['searchType']!);
    scrollController = _favSearchCtr.scrollController;
    scrollController.addListener(
      () {
        if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 300) {
          EasyThrottle.throttle('fav', const Duration(seconds: 1), () {
            _favSearchCtr.onLoad();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    scrollController.removeListener(() {});
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          // 批量移除入口（仅收藏夹内搜索可用）
          Obx(
            () => _favSearchCtr.canBatch
                ? IconButton(
                    tooltip: _favSearchCtr.batchMode.value ? '退出多选' : '批量移除',
                    icon: Icon(
                      _favSearchCtr.batchMode.value
                          ? Icons.close
                          : Icons.video_library_outlined,
                      size: 22,
                    ),
                    onPressed: () => _favSearchCtr.toggleBatchMode(),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
              onPressed: () => _favSearchCtr.submit(),
              icon: const Icon(Icons.search_outlined, size: 22)),
          const SizedBox(width: 10)
        ],
        title: Obx(
          () => TextField(
            autofocus: true,
            focusNode: _favSearchCtr.searchFocusNode,
            controller: _favSearchCtr.controller.value,
            textInputAction: TextInputAction.search,
            onChanged: (value) => _favSearchCtr.onChange(value),
            decoration: InputDecoration(
              hintText: _favSearchCtr.hintText,
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  Icons.clear,
                  size: 22,
                  color: Theme.of(context).colorScheme.outline,
                ),
                onPressed: () => _favSearchCtr.onClear(),
              ),
            ),
            onSubmitted: (String value) => _favSearchCtr.submit(),
          ),
        ),
      ),
      body: Obx(
        () => _favSearchCtr.loadingStatus.value && _favSearchCtr.favList.isEmpty
            ? ListView.builder(
                itemCount: 10,
                itemBuilder: (context, index) {
                  return const VideoCardHSkeleton();
                },
              )
            : _favSearchCtr.favList.isNotEmpty
                ? ListView.builder(
                    controller: scrollController,
                    itemCount: _favSearchCtr.favList.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _favSearchCtr.favList.length) {
                        return Container(
                          height: MediaQuery.of(context).padding.bottom + 60,
                          padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).padding.bottom),
                        );
                      } else {
                        return FavVideoCardH(
                          videoItem: _favSearchCtr.favList[index],
                          searchType: searchType,
                          isOwner: '0',
                          batchCtr: _favSearchCtr,
                          callFn: () => searchType != 1
                              ? _favSearchCtr
                                  .onCancelFav(_favSearchCtr.favList[index].id!)
                              : {},
                        );
                      }
                    },
                  )
                : const CustomScrollView(
                    slivers: <Widget>[
                      NoData(),
                    ],
                  ),
      ),
      // 批量移除操作栏
      bottomSheet: Obx(
        () => _favSearchCtr.batchMode.value
            ? SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color:
                            Theme.of(context).dividerColor.withOpacity(0.15),
                      ),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _favSearchCtr.selectAll(),
                          icon: const Icon(Icons.select_all_outlined,
                              size: 20),
                          label: Obx(
                            () => Text(
                              _favSearchCtr.favList.isNotEmpty &&
                                      _favSearchCtr.selectedAids.length ==
                                          _favSearchCtr.favList.length
                                  ? '取消全选'
                                  : '全选',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Obx(
                          () => FilledButton.icon(
                            onPressed: _favSearchCtr.selectedAids.isEmpty ||
                                    _favSearchCtr.batchRemoving.value
                                ? null
                                : () => _confirmRemoveSelected(context),
                            icon: _favSearchCtr.batchRemoving.value
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.delete_outline, size: 18),
                            label: Text(
                                '移除所选 (${_favSearchCtr.selectedAids.length})'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _confirmRemoveSelected(BuildContext context) async {
    SmartDialog.show(
      useSystem: true,
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('提示'),
          content: Text(
              '确定移除选中的 ${_favSearchCtr.selectedAids.length} 个视频吗？'),
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
                await _favSearchCtr.removeSelected();
              },
              child: const Text('确认移除'),
            ),
          ],
        );
      },
    );
  }
}
