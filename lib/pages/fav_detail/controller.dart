import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/user.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/user/fav_detail.dart';
import 'package:pilipala/models/user/fav_folder.dart';
import 'package:pilipala/pages/fav/index.dart';
import 'package:pilipala/utils/utils.dart';

class FavDetailController extends GetxController {
  FavFolderItemData? item;
  RxString title = ''.obs;

  int? mediaId;
  late String heroTag;
  int currentPage = 1;
  bool isLoadingMore = false;
  RxMap favInfo = {}.obs;
  RxList<FavDetailItemData> favList = <FavDetailItemData>[].obs;
  RxString loadingText = '加载中...'.obs;
  RxInt mediaCount = 0.obs;

  /// 批量移除收藏多选模式
  RxBool batchMode = false.obs;
  RxList<int> selectedAids = <int>[].obs;

  /// 是否收藏夹主人（响应式：入口按钮在 Obx 内读取，非 Rx 会导致
  /// Obx 无可观察对象而抛异常/不构建 → 批量移除按钮不显示）
  RxBool isOwner = false.obs;

  @override
  void onInit() {
    item = Get.arguments;
    title.value = item!.title!;
    if (Get.parameters.keys.isNotEmpty) {
      mediaId = int.parse(Get.parameters['mediaId']!);
      heroTag = Get.parameters['heroTag']!;
      isOwner.value = Get.parameters['isOwner'] == '1';
    }
    super.onInit();
  }

  Future<dynamic> queryUserFavFolderDetail({type = 'init'}) async {
    if (type == 'onLoad' && favList.length >= mediaCount.value) {
      loadingText.value = '没有更多了';
      return;
    }
    isLoadingMore = true;
    var res = await UserHttp.userFavFolderDetail(
      pn: currentPage,
      ps: 20,
      mediaId: mediaId!,
    );
    if (res['status']) {
      favInfo.value = res['data'].info;
      if (currentPage == 1 && type == 'init') {
        favList.value = res['data'].medias;
        mediaCount.value = res['data'].info['media_count'];
      } else if (type == 'onLoad') {
        favList.addAll(res['data'].medias);
      }
      if (favList.length >= mediaCount.value) {
        loadingText.value = '没有更多了';
      }
    }
    currentPage += 1;
    isLoadingMore = false;
    return res;
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

  onLoad() {
    queryUserFavFolderDetail(type: 'onLoad');
  }

  // ============ 失效视频一键移除 ============
  RxBool removingInvalid = false.obs;
  RxString invalidProgress = ''.obs;

  /// 当前已加载列表中的失效视频数（入口按钮展示用）
  int get invalidCount => favList.where((e) => e.isInvalid).length;

  /// 检查收藏夹内失效视频数量（分页拉全后判断，不依赖当前列表加载状态）
  Future<int> countInvalidVideos() async {
    int count = 0;
    int pn = 1;
    const int ps = 20;
    while (true) {
      var res = await UserHttp.userFavFolderDetail(
        pn: pn,
        ps: ps,
        mediaId: mediaId!,
      );
      if (res['status'] != true) break;
      final medias = res['data'].medias as List;
      if (medias.isEmpty) break;
      count += medias
          .whereType<FavDetailItemData>()
          .where((e) => e.isInvalid)
          .length;
      if (medias.length < ps) break;
      pn++;
    }
    return count;
  }

  /// 一键移除失效视频：调用官方“清空失效内容”接口（一次请求完成），
  /// 成功后重置列表回到第 1 页。
  Future<void> removeAllInvalidVideos() async {
    if (removingInvalid.value) return;
    removingInvalid.value = true;
    invalidProgress.value = '正在清理失效视频...';
    try {
      final res = await UserHttp.cleanFavResource(mediaId: mediaId!);
      SmartDialog.showToast(res['msg']);
      if (res['status'] == true) {
        // 重置回第 1 页重新加载
        currentPage = 1;
        favList.clear();
        await queryUserFavFolderDetail(type: 'init');
      }
    } finally {
      removingInvalid.value = false;
      invalidProgress.value = '';
    }
  }

  onDelFavFolder() async {
    SmartDialog.show(
      useSystem: true,
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('提示'),
          content: const Text('确定删除这个收藏夹吗？'),
          actions: [
            TextButton(
              onPressed: () async {
                SmartDialog.dismiss();
              },
              child: Text(
                '点错了',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () async {
                var res = await UserHttp.delFavFolder(mediaIds: mediaId!);
                SmartDialog.dismiss();
                SmartDialog.showToast(res['status'] ? '操作成功' : res['msg']);
                if (res['status']) {
                  FavController favController = Get.find<FavController>();
                  await favController.removeFavFolder(mediaIds: mediaId!);
                  Get.back();
                }
              },
              child: const Text('确认'),
            )
          ],
        );
      },
    );
  }

  onEditFavFolder() async {
    var res = await Get.toNamed(
      '/favEdit',
      arguments: {
        'mediaId': mediaId.toString(),
        'title': item!.title,
        'intro': item!.intro,
        'cover': item!.cover,
        'privacy': [23, 1].contains(item!.attr) ? 1 : 0,
      },
    );
    title.value = res['title'];
    print(title);
  }

  Future toViewPlayAll() async {
    final FavDetailItemData firstItem = favList.first;
    final String heroTag = Utils.makeHeroTag(firstItem.bvid);
    Get.toNamed(
      '/video?bvid=${firstItem.bvid}&cid=${firstItem.cid}',
      arguments: {
        'videoItem': firstItem,
        'heroTag': heroTag,
        'sourceType': 'fav',
        'mediaId': favInfo['id'],
        'oid': firstItem.id,
        'favTitle': favInfo['title'],
        'favInfo': favInfo,
        'count': favInfo['media_count'],
      },
    );
  }
}
