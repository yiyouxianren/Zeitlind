import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/search.dart';
import 'package:pilipala/models/common/search_type.dart';
import 'package:pilipala/models/search/result.dart';
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

  // 综合搜索返回的置顶 UP 主（独立请求，不阻塞视频列表）
  RxList pinnedUsers = [].obs;
  bool _pinnedLoaded = false;
  StreamSubscription<Set<int>>? _blacklistSub;

  @override
  void onInit() {
    super.onInit();
    // 黑名单变化（拉黑/移除/服务端同步）时，实时更新已渲染的列表
    _blacklistSub = BlacklistUpdateBus.stream.listen((_) => _onBlacklistChanged());
  }

  @override
  void onClose() {
    _blacklistSub?.cancel();
    super.onClose();
  }

  void _onBlacklistChanged() {
    _reapplyPinned();
    final filtered = _filterVideos(resultList);
    if (filtered.length != resultList.length) {
      resultList.value = filtered;
    }
  }

  /// 结果中的视频条目（含黑名单 UP 的）实时过滤
  List _filterVideos(List list) {
    return list
        .where((item) =>
            item is SearchUserItemModel ||
            !BlacklistFilter.isBlocked(item is SearchVideoItemModel
                ? (item.mid ?? item.owner?.mid)
                : null))
        .toList();
  }

  Future onSearch({type = 'init'}) async {
    // 视频结果页首屏/刷新：并行拉取综合搜索，取置顶 UP 主卡片插到列表头部
    if ((type == 'init' || type == 'onRefresh') &&
        searchType == SearchType.video) {
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
        if (type == 'init') {
          // 首屏后置 UP 卡片若已就绪需合并一次
          _reapplyPinned();
        }
      }
      page.value++;
      onPushDetail(keyword, resultList);
    }
    return result;
  }

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
              _reapplyPinned();
            }
          }
        }
      }
    } catch (_) {
      // 综合搜索失败不影响视频结果
    }
  }

  /// 把置顶 UP 主卡片合并进结果列表头部（幂等，可重复调用）。
  void _reapplyPinned() {
    final videos = _filterVideos(
      resultList.where((i) => i is! SearchUserItemModel).toList(),
    );
    if (pinnedUsers.isEmpty) {
      if (resultList.length != videos.length) {
        resultList.value = videos;
      }
      return;
    }
    final merged = [...pinnedUsers, ...videos];
    resultList.value = merged;
  }

  /// 仅在刷新拿到新数据时调用：以新列表为基座重插置顶卡片
  void _applyPinned(List baseList) {
    final videos = _filterVideos(baseList);
    if (pinnedUsers.isEmpty) {
      resultList.value = videos;
      return;
    }
    resultList.value = [...pinnedUsers, ...videos];
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
