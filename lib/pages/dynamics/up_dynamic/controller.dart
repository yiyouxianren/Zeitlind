import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/dynamics.dart';
import 'package:pilipala/models/dynamics/result.dart';
import 'package:pilipala/models/dynamics/up.dart';

class UpDynamicsController extends GetxController {
  UpDynamicsController(this.upInfo);
  UpItem upInfo;
  RxList<DynamicItemModel> dynamicsList = <DynamicItemModel>[].obs;
  RxBool isLoadingDynamic = false.obs;
  String? offset = '';
  int page = 1;
  bool _hasMore = true;

  Future queryFollowDynamic({type = 'init'}) async {
    if (isLoadingDynamic.value) {
      return {'status': false, 'msg': '正在加载'};
    }
    if (type == 'init') {
      page = 1;
      offset = '';
      _hasMore = true;
      dynamicsList.clear();
    } else if (!_hasMore) {
      return {'status': true, 'data': null};
    }
    isLoadingDynamic.value = true;
    try {
      var res = await DynamicsHttp.followDynamic(
        page: page,
        type: 'all',
        offset: offset,
        mid: upInfo.mid,
      );
      if (res['status']) {
        final DynamicsDataModel data = res['data'];
        final List<DynamicItemModel> items = data.items ?? <DynamicItemModel>[];
        if (type == 'init') {
          dynamicsList.value = items;
        } else {
          dynamicsList.addAll(items);
        }
        final previousOffset = offset?.trim() ?? '';
        final nextOffset = data.offset?.trim() ?? '';
        _hasMore = data.hasMore == true &&
            nextOffset.isNotEmpty &&
            (type == 'init' || nextOffset != previousOffset);
        offset = nextOffset;
        if (_hasMore) {
          page++;
        } else if (type == 'onLoad') {
          SmartDialog.showToast('没有更多了');
        }
      } else if (type == 'onLoad') {
        SmartDialog.showToast(res['msg'] ?? '动态加载失败');
      }
      return res;
    } finally {
      isLoadingDynamic.value = false;
    }
  }
}
