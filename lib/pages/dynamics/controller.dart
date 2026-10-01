// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/dynamics.dart';
import 'package:pilipala/http/search.dart';
import 'package:pilipala/models/common/dynamics_type.dart';
import 'package:pilipala/models/dynamics/result.dart';
import 'package:pilipala/models/dynamics/up.dart';
import 'package:pilipala/models/live/item.dart';
import 'package:pilipala/utils/dynamic_filter.dart';
import 'package:pilipala/utils/feed_back.dart';
import 'package:pilipala/utils/id_utils.dart';
import 'package:pilipala/utils/route_push.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:pilipala/models/user/info.dart';

class DynamicsController extends GetxController {
  int page = 1;
  String? offset = '';
  RxList<DynamicItemModel> dynamicsList = <DynamicItemModel>[].obs;
  Rx<DynamicsType> dynamicsType = DynamicsType.values[0].obs;
  RxString dynamicsTypeLabel = '全部'.obs;
  final ScrollController scrollController = ScrollController();
  Rx<FollowUpModel> upData = FollowUpModel().obs;
  // 默认获取全部动态
  RxInt mid = (-1).obs;
  Rx<UpItem> upInfo = UpItem().obs;
  List filterTypeList = [
    {
      'label': DynamicsType.all.labels,
      'value': DynamicsType.all,
      'enabled': true
    },
    {
      'label': DynamicsType.video.labels,
      'value': DynamicsType.video,
      'enabled': true
    },
    {
      'label': DynamicsType.pgc.labels,
      'value': DynamicsType.pgc,
      'enabled': true
    },
    {
      'label': DynamicsType.article.labels,
      'value': DynamicsType.article,
      'enabled': true
    },
  ];
  bool flag = false;
  RxInt initialValue = 0.obs;
  Box userInfoCache = GStrorage.userInfo;
  RxBool userLogin = false.obs;
  dynamic userInfo;
  RxBool isLoadingDynamic = false.obs;
  bool _hasMore = true;
  Box setting = GStrorage.setting;

  @override
  void onInit() {
    userInfo = userInfoCache.get('userInfoCache');
    userLogin.value = userInfo is UserInfoData &&
        userInfo.isLogin == true &&
        userInfo.mid != null;
    super.onInit();
    initialValue.value =
        setting.get(SettingBoxKey.defaultDynamicType, defaultValue: 0);
    dynamicsType = DynamicsType.values[initialValue.value].obs;
  }

  Future queryFollowDynamic({type = 'init'}) async {
    if (!userLogin.value) {
      return {'status': false, 'msg': '账号未登录', 'code': -101};
    }
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
        type: dynamicsType.value.values,
        offset: offset,
        mid: mid.value,
      );
      if (res['status']) {
        final DynamicsDataModel data = res['data'];
        final List<DynamicItemModel> items =
            (data.items ?? <DynamicItemModel>[])
                .where((item) => !DynamicFilter.shouldBlock(item))
                .toList();
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

  onSelectType(value) async {
    dynamicsType.value = filterTypeList[value]['value'];
    dynamicsList.value = <DynamicItemModel>[];
    page = 1;
    offset = '';
    _hasMore = true;
    initialValue.value = value;
    await queryFollowDynamic();
    scrollController.jumpTo(0);
  }

  pushDetail(item, floor, {action = 'all'}) async {
    feedBack();

    /// 点击评论action 直接查看评论
    if (action == 'comment') {
      Get.toNamed('/dynamicDetail',
          arguments: {'item': item, 'floor': floor, 'action': action});
      return false;
    }
    switch (item!.type) {
      /// 转发的动态
      case 'DYNAMIC_TYPE_FORWARD':
        final orig = item.orig;
        if (orig != null) {
          Get.toNamed('/dynamicDetail',
              arguments: {'item': orig, 'floor': floor});
        } else {
          Get.toNamed('/dynamicDetail',
              arguments: {'item': item, 'floor': floor});
        }
        break;

      /// 图文/专栏动态查看
      case 'DYNAMIC_TYPE_DRAW':
        final opus = item.modules?.moduleDynamic?.major?.opus;
        final jumpUrl = opus?.jumpUrl ?? '';
        final match = RegExp(r'/opus/(\d+)').firstMatch(jumpUrl);
        if (match != null) {
          Get.toNamed('/opus', parameters: {
            'title': opus?.title ?? '专栏',
            'id': match.group(1)!,
            'articleType': 'opus',
          }, arguments: {
            'dynamicItem': item
          });
        } else {
          Get.toNamed('/dynamicDetail',
              arguments: {'item': item, 'floor': floor});
        }
        break;
      case 'DYNAMIC_TYPE_AV':
        String bvid = item.modules.moduleDynamic.major.archive.bvid;
        String cover = item.modules.moduleDynamic.major.archive.cover;
        try {
          int cid = await SearchHttp.ab2c(bvid: bvid);
          Get.toNamed('/video?bvid=$bvid&cid=$cid',
              arguments: {'pic': cover, 'heroTag': bvid});
        } catch (err) {
          SmartDialog.showToast(err.toString());
        }
        break;

      /// 专栏文章查看
      case 'DYNAMIC_TYPE_ARTICLE':
        final opus = item.modules?.moduleDynamic?.major?.opus;
        final String title = opus?.title ?? '专栏';
        final String jumpUrl = opus?.jumpUrl ?? '';
        final String url =
            jumpUrl.startsWith('//') ? jumpUrl.substring(2) : jumpUrl;
        final Match? match =
            RegExp(r'/(opus|read)/(?:cv)?(\d+)').firstMatch(url);
        if (match != null) {
          final String type = match.group(1)!;
          final String number = match.group(2)!;
          if (type == 'opus') {
            Get.toNamed('/opus', parameters: {
              'title': title,
              'id': number,
              'articleType': 'opus',
            }, arguments: {
              'dynamicItem': item
            });
          } else {
            Get.toNamed('/read', parameters: {
              'title': title,
              'id': number,
              'articleType': type,
            });
          }
        } else if (url.isNotEmpty) {
          Get.toNamed('/dynamicDetail',
              arguments: {'item': item, 'floor': floor});
        }
        break;
      case 'DYNAMIC_TYPE_PGC':
      case 'DYNAMIC_TYPE_PGC_UNION':
        final major = item.modules?.moduleDynamic?.major;
        final pgc = major?.pgc ?? major?.archive;
        int? seasonId = pgc?.seasonId;
        int? epId = pgc?.epid;
        final jumpUrl = pgc?.jumpUrl ?? '';
        if (epId == null || seasonId == null) {
          final epMatch = RegExp(r'/ep(\d+)').firstMatch(jumpUrl);
          final seasonMatch = RegExp(r'/ss(\d+)').firstMatch(jumpUrl);
          epId ??= epMatch == null ? null : int.tryParse(epMatch.group(1)!);
          seasonId ??=
              seasonMatch == null ? null : int.tryParse(seasonMatch.group(1)!);
        }
        if (seasonId != null || epId != null) {
          await RoutePush.bangumiPush(seasonId, epId);
        } else if (jumpUrl.isNotEmpty) {
          Get.toNamed('/webview', parameters: {
            'url': jumpUrl.startsWith('//') ? 'https:$jumpUrl' : jumpUrl,
            'type': 'webview',
            'pageTitle': pgc?.title ?? '番剧',
          });
        } else {
          SmartDialog.showToast('番剧信息不完整');
        }
        break;

      /// 纯文字动态查看
      case 'DYNAMIC_TYPE_WORD':
        print('纯文本');
        Get.toNamed('/dynamicDetail',
            arguments: {'item': item, 'floor': floor});
        break;
      case 'DYNAMIC_TYPE_LIVE_RCMD':
        DynamicLiveModel liveRcmd = item.modules.moduleDynamic.major.liveRcmd;
        ModuleAuthorModel author = item.modules.moduleAuthor;
        LiveItemModel liveItem = LiveItemModel.fromJson({
          'title': liveRcmd.title,
          'uname': author.name,
          'cover': liveRcmd.cover,
          'mid': author.mid,
          'face': author.face,
          'roomid': liveRcmd.roomId,
          'watched_show': liveRcmd.watchedShow,
        });
        Get.toNamed('/liveRoom?roomid=${liveItem.roomId}', arguments: {
          'liveItem': liveItem,
          'heroTag': liveItem.roomId.toString()
        });
        break;

      /// 合集查看
      case 'DYNAMIC_TYPE_UGC_SEASON':
        DynamicArchiveModel ugcSeason =
            item.modules.moduleDynamic.major.ugcSeason;
        int aid = ugcSeason.aid!;
        String bvid = IdUtils.av2bv(aid);
        String cover = ugcSeason.cover!;
        int cid = await SearchHttp.ab2c(bvid: bvid);
        Get.toNamed('/video?bvid=$bvid&cid=$cid',
            arguments: {'pic': cover, 'heroTag': bvid});
        break;
    }
  }

  Future queryFollowUp({type = 'init'}) async {
    if (!userLogin.value) {
      return {'status': false, 'msg': '账号未登录', 'code': -101};
    }
    if (type == 'init') {
      upData.value.upList = <UpItem>[];
      upData.value.liveList = <LiveUserItem>[];
    }
    var res = await DynamicsHttp.followUp();
    if (res['status']) {
      upData.value = res['data'];
      final upList = upData.value.upList ?? <UpItem>[];
      if (upList.isEmpty) {
        mid.value = -1;
      }
      upList.insertAll(0, [
        UpItem(face: '', uname: '全部动态', mid: -1),
        UpItem(
          face: userInfo?.face ?? '',
          uname: userInfo?.uname ?? '我',
          mid: userInfo?.mid ?? -1,
        ),
      ]);
      upData.value.upList = upList;
    }
    return res;
  }

  onSelectUp(mid) async {
    this.mid.value = mid;
    dynamicsType.value = DynamicsType.values[0];
    dynamicsList.value = <DynamicItemModel>[];
    page = 1;
    offset = '';
    _hasMore = true;
    await queryFollowDynamic();
  }

  onRefresh() async {
    await queryFollowUp();
    return queryFollowDynamic();
  }

  // 返回顶部并刷新
  void animateToTop() async {
    if (!scrollController.hasClients) return;
    if (scrollController.offset >=
        MediaQuery.of(Get.context!).size.height * 5) {
      scrollController.jumpTo(0);
    } else {
      await scrollController.animateTo(0,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
  }

  // 重置搜索
  void resetSearch() {
    mid.value = -1;
    dynamicsType.value = DynamicsType.values[0];
    initialValue.value = 0;
    SmartDialog.showToast('还原默认加载');
    dynamicsList.value = <DynamicItemModel>[];
    page = 1;
    offset = '';
    _hasMore = true;
    queryFollowDynamic();
  }

  // 点击up主
  void onTapUp(data) {
    mid.value = data.mid;
    upInfo.value = data;
    onSelectUp(data.mid);
  }
}
