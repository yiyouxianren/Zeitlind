import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/model_hot_video_item.dart';

class HotController extends GetxController {
  final ScrollController scrollController = ScrollController();
  final int _count = 20;
  int _currentPage = 1;
  RxList<HotVideoItemModel> videoList = <HotVideoItemModel>[].obs;
  bool isLoadingMore = false;
  // 与 B 站网页端一致：热门为固定榜单，翻页到头后不再请求
  bool hasMore = true;
  OverlayEntry? popupDialog;

  // 获取推荐
  Future queryHotFeed(type) async {
    // 下拉刷新回到第 1 页：重新取榜首内容整表替换，
    // 避免旧数据无限前插导致列表越来越长、内容越刷越杂
    if (type == 'onRefresh') {
      _currentPage = 1;
      hasMore = true;
    }
    if (!hasMore && type == 'onLoad') {
      return {'status': false, 'msg': '没有更多'};
    }
    var res = await VideoHttp.hotVideoList(
      pn: _currentPage,
      ps: _count,
    );
    if (res['status']) {
      final List<HotVideoItemModel> list = res['data'];
      if (type == 'init' || type == 'onRefresh') {
        videoList.value = list;
      } else if (type == 'onLoad') {
        // 服务端翻页返回空列表视为榜单到底
        if (list.isEmpty) {
          hasMore = false;
        } else {
          videoList.addAll(list);
        }
      }
      _currentPage += 1;
    }
    isLoadingMore = false;
    return res;
  }

  // 下拉刷新
  Future onRefresh() async {
    queryHotFeed('onRefresh');
  }

  // 上拉加载
  Future onLoad() async {
    queryHotFeed('onLoad');
  }

  // 返回顶部并刷新
  void animateToTop() async {
    if (scrollController.offset >=
        MediaQuery.of(Get.context!).size.height * 5) {
      scrollController.jumpTo(0);
    } else {
      await scrollController.animateTo(0,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
  }
}
