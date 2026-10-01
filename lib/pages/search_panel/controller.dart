import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/search.dart';
import 'package:pilipala/models/common/search_type.dart';
import 'package:pilipala/utils/blacklist_filter.dart';
import 'package:pilipala/utils/id_utils.dart';
import 'package:pilipala/utils/utils.dart';

class SearchPanelController extends GetxController {
  SearchPanelController({this.keyword, this.searchType});
  ScrollController scrollController = ScrollController();
  String? keyword;
  SearchType? searchType;
  RxInt page = 1.obs;
  RxList resultList = [].obs;
  // 结果排序方式 搜索类型为视频、专栏及相簿时
  RxString order = ''.obs;
  // 视频时长筛选 仅用于搜索视频
  RxInt duration = 0.obs;
  // 视频分区筛选 仅用于搜索视频 -1时不传
  RxInt tids = (-1).obs;

  Future onSearch({type = 'init'}) async {
    // 视频结果页首屏：并行拉取综合搜索，取置顶 UP 主卡片插到列表头部
    if (type == 'init' && searchType == SearchType.video) {
      queryPinnedUsers();
    }
    var result = await SearchHttp.searchByType(
      searchType: searchType!,
      keyword: keyword!,
      page: page.value,
      order: !['video', 'article'].contains(searchType!.type)
          ? null
          : (order.value == '' ? null : order.value),
      duration: searchType!.type != 'video' ? null : duration.value,
      tids: searchType!.type != 'video' ? null : tids.value,
    );
    if (result['status']) {
      if (type == 'onRefresh') {
        _applyPinned(result['data'].list ?? []);
      } else {
        resultList.addAll(result['data'].list ?? []);
      }
      page.value++;
      onPushDetail(keyword, resultList);
    }
    return result;
  }

  // 综合搜索返回的置顶 UP 主（独立请求，不阻塞视频列表）
  RxList pinnedUsers = [].obs;
  bool _pinnedLoaded = false;

  Future<void> queryPinnedUsers() async {
    if (_pinnedLoaded) return;
    _pinnedLoaded = true;
    try {
      final res = await SearchHttp.searchAll(keyword: keyword!);
      if (res['status'] == true) {
        final users = res['data'].users ?? [];
        if (users.isNotEmpty) {
          // 黑名单开启时：屏蔽黑名单 UP 的推荐卡片（与视频结果的过滤规则一致）
          final visible = BlacklistFilter.filter(
            users,
            (dynamic item) => item.mid,
          );
          if (visible.isNotEmpty) {
            pinnedUsers.value = visible.take(3).toList();
            // 若视频列表已就绪，把 UP 主卡片插到最前
            if (resultList.isNotEmpty) {
              _applyPinned(List.from(resultList));
            }
          }
        }
      }
    } catch (_) {
      // 综合搜索失败不影响视频结果
    }
  }

  /// 把置顶 UP 主合并进结果列表头部（去重，避免重复插入）。
  void _applyPinned(List baseList) {
    if (pinnedUsers.isEmpty) {
      resultList.value = baseList;
      return;
    }
    final merged = [...pinnedUsers, ...baseList];
    // 用户 item 是 SearchUserItemModel，视频是 SearchVideoItemModel，类型天然可区分
    resultList.value = merged;
  }

  Future onRefresh() async {
    page.value = 1;
    _pinnedLoaded = false;
    pinnedUsers.clear();
    await onSearch(type: 'onRefresh');
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

  void onPushDetail(keyword, resultList) async {
    // 匹配输入内容，如果是AV、BV号且有结果 直接跳转详情页
    Map matchRes = IdUtils.matchAvorBv(input: keyword);
    List matchKeys = matchRes.keys.toList();
    String? bvid;
    try {
      bvid = resultList.first.bvid;
    } catch (_) {
      bvid = null;
    }
    // keyword 可能输入纯数字
    int? aid;
    try {
      aid = resultList.first.aid;
    } catch (_) {
      aid = null;
    }
    if (matchKeys.isNotEmpty && searchType == SearchType.video ||
        aid.toString() == keyword) {
      String heroTag = Utils.makeHeroTag(bvid);
      int cid = await SearchHttp.ab2c(aid: aid, bvid: bvid);
      if (matchKeys.isNotEmpty &&
              matchKeys.first == 'BV' &&
              matchRes[matchKeys.first] == bvid ||
          matchKeys.isNotEmpty &&
              matchKeys.first == 'AV' &&
              matchRes[matchKeys.first] == aid ||
          aid.toString() == keyword) {
        Get.toNamed(
          '/video?bvid=$bvid&cid=$cid',
          arguments: {'videoItem': resultList.first, 'heroTag': heroTag},
        );
      }
    }
  }
}
