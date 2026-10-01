import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/live.dart';
import 'package:pilipala/models/live/follow.dart';
import 'package:pilipala/models/live/item.dart';
import 'package:pilipala/utils/blacklist_filter.dart';
import 'package:pilipala/utils/storage.dart';

class LiveController extends GetxController {
  final ScrollController scrollController = ScrollController();
  int count = 30;
  int _currentPage = 1;
  RxInt crossAxisCount = 2.obs;
  RxList<LiveItemModel> liveList = <LiveItemModel>[].obs;
  RxList<LiveFollowingItemModel> liveFollowingList =
      <LiveFollowingItemModel>[].obs;
  bool _isLoading = false;
  bool _isRefreshing = false;
  int _requestGeneration = 0;
  bool flag = false;
  OverlayEntry? popupDialog;
  Box setting = GStrorage.setting;

  @override
  void onInit() {
    super.onInit();
    crossAxisCount.value =
        setting.get(SettingBoxKey.customRows, defaultValue: 2);
  }

  // 获取推荐
  Future queryLiveList(type) async {
    final bool isRefresh = type == 'init';
    if (_isRefreshing && !isRefresh) {
      return {'status': false, 'msg': '正在刷新'};
    }
    if (_isLoading && !isRefresh) {
      return {'status': false, 'msg': '正在加载'};
    }
    if (isRefresh) {
      _currentPage = 1;
      _requestGeneration += 1;
      _isRefreshing = true;
    }
    final int requestGeneration = _requestGeneration;
    _isLoading = true;
    try {
      final res = await LiveHttp.liveList(
        pn: _currentPage,
        ps: count,
      );
      if (res['status'] && requestGeneration == _requestGeneration) {
        final filtered = (res['data'] as Iterable<LiveItemModel>)
            .where((item) => !BlacklistFilter.isBlocked(item.uid))
            .toList();
        if (isRefresh) {
          liveList.value = filtered;
        } else if (type == 'onLoad' && filtered.isNotEmpty) {
          final existingIds = liveList.map((item) => item.roomId).toSet();
          liveList.addAll(filtered.where(
            (LiveItemModel item) => !existingIds.contains(item.roomId),
          ));
        }
        _currentPage += 1;
      }
      return res;
    } finally {
      _isLoading = false;
      if (isRefresh && requestGeneration == _requestGeneration) {
        _isRefreshing = false;
      }
    }
  }

  // 下拉刷新
  Future onRefresh() async {
    await Future.wait([
      queryLiveList('init'),
      fetchLiveFollowing(),
    ]);
  }

  // 上拉加载
  Future onLoad() async {
    await queryLiveList('onLoad');
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

  Future fetchLiveFollowing() async {
    var res = await LiveHttp.liveFollowing(pn: 1, ps: 20);
    if (res['status']) {
      liveFollowingList.value = res['data']
          .list
          .where((LiveFollowingItemModel item) =>
              item.liveStatus == 1 &&
              item.recordLiveTime == 0 &&
              !BlacklistFilter.isBlocked(item.uid))
          .toList();
    }
    return res;
  }
}
