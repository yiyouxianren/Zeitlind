import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/user.dart';
import 'package:pilipala/models/user/fav_detail.dart';

import '../../http/video.dart';

class FavSearchController extends GetxController {
  final ScrollController scrollController = ScrollController();
  Rx<TextEditingController> controller = TextEditingController().obs;
  final FocusNode searchFocusNode = FocusNode();
  RxString searchKeyWord = ''.obs; // 搜索词
  String hintText = '请输入已收藏视频名称'; // 默认
  RxBool loadingStatus = false.obs; // 加载状态
  RxString loadingText = '加载中...'.obs; // 加载提示
  bool hasMore = false;
  late int searchType;
  late int mediaId;

  int currentPage = 1; // 当前页
  int count = 0; // 总数
  RxList<FavDetailItemData> favList = <FavDetailItemData>[].obs;

  /// 批量移除多选模式（仅 searchType==0 即指定收藏夹内搜索时可用）
  RxBool batchMode = false.obs;
  RxList<int> selectedAids = <int>[].obs;
  RxBool batchRemoving = false.obs;

  @override
  void onInit() {
    super.onInit();
    searchType = int.parse(Get.parameters['searchType']!);
    mediaId = int.parse(Get.parameters['mediaId']!);
  }

  // 清空搜索
  void onClear() {
    if (searchKeyWord.value.isNotEmpty && controller.value.text != '') {
      controller.value.clear();
      searchKeyWord.value = '';
    } else {
      Get.back();
    }
  }

  void onChange(value) {
    searchKeyWord.value = value;
  }

  //  提交搜索内容
  void submit() {
    loadingStatus.value = true;
    currentPage = 1;
    searchFav();
  }

  // 搜索收藏夹视频
  Future searchFav({type = 'init'}) async {
    var res = await await UserHttp.userFavFolderDetail(
      pn: currentPage,
      ps: 20,
      mediaId: mediaId,
      keyword: searchKeyWord.value,
      type: searchType,
    );
    if (res['status']) {
      if (currentPage == 1 && type == 'init') {
        favList.value = res['data'].medias;
      } else if (type == 'onLoad') {
        favList.addAll(res['data'].medias);
      }
      hasMore = res['data'].hasMore;
    }
    currentPage += 1;
    loadingStatus.value = false;
  }

  onLoad() {
    if (!hasMore) return;
    searchFav(type: 'onLoad');
  }

  onCancelFav(int id) async {
    var result = await VideoHttp.favVideo(
        aid: id, addIds: '', delIds: mediaId.toString());
    if (result['status']) {
      List dataList = favList;
      for (var i in dataList) {
        if (i.id == id) {
          dataList.remove(i);
          break;
        }
      }
      SmartDialog.showToast('取消收藏');
    }
  }

  // ============ 批量移除（官方 batch-del 接口） ============

  /// 是否允许批量操作：仅“指定收藏夹内搜索”（searchType==0）时可用
  bool get canBatch => searchType == 0;

  void toggleBatchMode() {
    batchMode.value = !batchMode.value;
    if (!batchMode.value) {
      selectedAids.clear();
    }
  }

  void toggleSelect(int aid) {
    if (selectedAids.contains(aid)) {
      selectedAids.remove(aid);
    } else {
      selectedAids.add(aid);
    }
  }

  void selectAll() {
    if (selectedAids.length == favList.length && favList.isNotEmpty) {
      selectedAids.clear();
    } else {
      selectedAids.value = favList.map((e) => e.id!).toList();
    }
  }

  /// 批量移除勾选的视频：一次请求官方批量取消收藏接口
  Future<void> removeSelected() async {
    if (batchRemoving.value || selectedAids.isEmpty) return;
    batchRemoving.value = true;
    try {
      final res = await VideoHttp.favBatchDel(
        aids: selectedAids.toList(),
        mediaId: mediaId,
      );
      SmartDialog.showToast(res['msg']);
      if (res['status'] == true) {
        // 从当前搜索结果中移除已删条目，保持列表与搜索上下文一致
        favList.removeWhere((e) => selectedAids.contains(e.id));
        count = favList.length;
        selectedAids.clear();
        batchMode.value = false;
        favList.refresh();
      }
    } finally {
      batchRemoving.value = false;
    }
  }
}
