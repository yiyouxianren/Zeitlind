import 'dart:async';

import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/skeleton/video_card_h.dart';
import 'package:pilipala/common/widgets/http_error.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/common/widgets/no_data.dart';
import 'package:pilipala/pages/fav_detail/index.dart';

import 'widget/batch_unfav_bar.dart';
import 'widget/fav_video_card.dart';

class FavDetailPage extends StatefulWidget {
  const FavDetailPage({super.key});

  @override
  State<FavDetailPage> createState() => _FavDetailPageState();
}

class _FavDetailPageState extends State<FavDetailPage> {
  late final ScrollController _controller = ScrollController();
  final FavDetailController _favDetailController =
      Get.put(FavDetailController());
  late StreamController<bool> titleStreamC =
      StreamController<bool>.broadcast(); // a
  Future? _futureBuilderFuture;
  late String mediaId;

  @override
  void initState() {
    super.initState();
    mediaId = Get.parameters['mediaId']!;
    _futureBuilderFuture = _favDetailController.queryUserFavFolderDetail();
    _controller.addListener(
      () {
        if (_controller.offset > 160) {
          titleStreamC.add(true);
        } else if (_controller.offset <= 160) {
          titleStreamC.add(false);
        }

        if (_controller.position.pixels >=
            _controller.position.maxScrollExtent - 200) {
          EasyThrottle.throttle('favDetail', const Duration(seconds: 1), () {
            _favDetailController.onLoad();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    titleStreamC.close();
    super.dispose();
  }

  /// 一键移除失效视频：先统计数量，确认后执行
  Future<void> _onRemoveInvalidVideos(BuildContext context) async {
    SmartDialog.showLoading(msg: '正在检查失效视频...');
    int count = 0;
    try {
      count = await _favDetailController.countInvalidVideos();
    } catch (_) {
      count = _favDetailController.invalidCount;
    }
    SmartDialog.dismiss();
    if (!mounted) return;
    if (count == 0) {
      SmartDialog.showToast('没有发现失效视频');
      return;
    }
    SmartDialog.show(
      useSystem: true,
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('提示'),
          content: Text('检测到 $count 个失效视频，确定全部移除吗？'),
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
                await _favDetailController.removeAllInvalidVideos();
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
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
        controller: _controller,
        slivers: [
          SliverAppBar(
            expandedHeight: 260 - MediaQuery.of(context).padding.top,
            pinned: true,
            titleSpacing: 0,
            title: StreamBuilder(
              stream: titleStreamC.stream.distinct(),
              initialData: false,
              builder: (context, AsyncSnapshot snapshot) {
                return AnimatedOpacity(
                  opacity: snapshot.data ? 1 : 0,
                  curve: Curves.easeOut,
                  duration: const Duration(milliseconds: 500),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Obx(
                            () => Text(
                              _favDetailController.title.value,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '共${_favDetailController.mediaCount}条视频',
                            style: Theme.of(context).textTheme.labelMedium,
                          )
                        ],
                      )
                    ],
                  ),
                );
              },
            ),
            actions: [
              // 批量移除收藏入口（仅自己的收藏夹）
              Obx(
                () => _favDetailController.isOwner.value &&
                        !_favDetailController.batchMode.value
                    ? IconButton(
                        tooltip: '批量移除',
                        icon: const Icon(Icons.video_library_outlined,
                            size: 22),
                        onPressed: () {
                          _favDetailController.batchMode.value = true;
                        },
                      )
                    : const SizedBox.shrink(),
              ),
              IconButton(
                onPressed: () =>
                    Get.toNamed('/favSearch?searchType=0&mediaId=$mediaId'),
                icon: const Icon(Icons.search_outlined),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_outlined),
                position: PopupMenuPosition.under,
                onSelected: (String type) {},
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    onTap: () => _favDetailController.onEditFavFolder(),
                    value: 'edit',
                    child: const Text('编辑收藏夹'),
                  ),
                  PopupMenuItem<String>(
                    onTap: () => _favDetailController.onDelFavFolder(),
                    value: 'pause',
                    child: const Text('删除收藏夹'),
                  ),
                  // 一键移除失效视频（仅自己的收藏夹）
                  if (_favDetailController.isOwner.value)
                    PopupMenuItem<String>(
                      onTap: () => _onRemoveInvalidVideos(context),
                      value: 'removeInvalid',
                      enabled: !_favDetailController.removingInvalid.value,
                      child: const Text('一键移除失效视频'),
                    ),
                ],
              ),
              const SizedBox(width: 14),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.2),
                    ),
                  ),
                ),
                padding: EdgeInsets.only(
                    top: kTextTabBarHeight +
                        MediaQuery.of(context).padding.top +
                        30,
                    left: 20,
                    right: 20),
                child: SizedBox(
                  height: 200,
                  child: Row(
                    // mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag: _favDetailController.heroTag,
                        child: NetworkImgLayer(
                          width: 180,
                          height: 110,
                          src: _favDetailController.item!.cover,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Obx(
                              () => Text(
                                _favDetailController.title.value,
                                style: TextStyle(
                                    fontSize: Theme.of(context)
                                        .textTheme
                                        .titleMedium!
                                        .fontSize,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _favDetailController.item!.upper!.name!,
                              style: TextStyle(
                                  fontSize: Theme.of(context)
                                      .textTheme
                                      .labelSmall!
                                      .fontSize,
                                  color: Theme.of(context).colorScheme.outline),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 15, bottom: 8, left: 14),
              child: Obx(
                () => Text(
                  '共${_favDetailController.mediaCount}条视频',
                  style: TextStyle(
                      fontSize:
                          Theme.of(context).textTheme.labelMedium!.fontSize,
                      color: Theme.of(context).colorScheme.outline,
                      letterSpacing: 1),
                ),
              ),
            ),
          ),
          FutureBuilder(
            future: _futureBuilderFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                Map data = snapshot.data;
                if (data['status']) {
                  if (_favDetailController.item!.mediaCount == 0) {
                    return const NoData();
                  } else {
                    // Obx 监听 batchMode/favList：进入批量模式或列表变化时
                    // 整个 SliverList 重建（卡片显示/隐藏勾选框由此驱动；
                    // 单个勾选的即时刷新由卡片自身 setState 完成）
                    return Obx(() {
                      // 触发依赖：batchMode 变化时重建列表
                      final bool batch = _favDetailController.batchMode.value;
                      final List favList = _favDetailController.favList;
                      return favList.isEmpty
                          ? const SliverToBoxAdapter(child: SizedBox())
                          : SliverList(
                              key: ValueKey('fav-batch-$batch'),
                              delegate:
                                  SliverChildBuilderDelegate((context, index) {
                                return FavVideoCardH(
                                  videoItem: favList[index],
                                  isOwner:
                                      _favDetailController.isOwner.value
                                          ? '1'
                                          : '0',
                                  batchCtr: _favDetailController,
                                  callFn: () => _favDetailController
                                      .onCancelFav(favList[index].id),
                                );
                              }, childCount: favList.length),
                            );
                    });
                  }
                } else {
                  return HttpError(
                    errMsg: data['msg'],
                    fn: () => setState(() {}),
                  );
                }
              } else {
                // 骨架屏
                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return const VideoCardHSkeleton();
                  }, childCount: 10),
                );
              }
            },
          ),
          SliverToBoxAdapter(
            child: Container(
              height: MediaQuery.of(context).padding.bottom + 60,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom),
              child: Center(
                child: Obx(
                  () => Text(
                    _favDetailController.removingInvalid.value
                        ? _favDetailController.invalidProgress.value
                        : _favDetailController.loadingText.value,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 13),
                  ),
                ),
              ),
            ),
          )
          ],
        ),
          // 批量移除收藏多选操作栏
          Obx(
            () => _favDetailController.batchMode.value
                ? Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: BatchUnfavBar(ctr: _favDetailController),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: Obx(
        () => _favDetailController.mediaCount > 0
            ? FloatingActionButton.extended(
                onPressed: _favDetailController.toViewPlayAll,
                label: const Text('播放全部'),
                icon: const Icon(Icons.playlist_play),
              )
            : const SizedBox(),
      ),
    );
  }
}
