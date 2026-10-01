import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/models/common/tab_type.dart';
import 'package:pilipala/models/user/info.dart';
import 'package:pilipala/utils/simple_mode_service.dart';
import 'package:pilipala/utils/storage.dart';
import 'widgets/simple_fav_page.dart';
import '../../http/index.dart';

class HomeController extends GetxController with GetTickerProviderStateMixin {
  bool flag = false;
  late RxList tabs = [].obs;
  RxInt initialIndex = 1.obs;
  late TabController tabController;
  late List tabsCtrList;
  late List<Widget> tabsPageList;
  Box userInfoCache = GStrorage.userInfo;
  Box settingStorage = GStrorage.setting;
  RxBool userLogin = false.obs;
  RxString userFace = ''.obs;
  var userInfo;
  Box setting = GStrorage.setting;
  late final StreamController<bool> searchBarStream =
      StreamController<bool>.broadcast();
  late bool hideSearchBar;
  late List defaultTabs;
  late List<String> tabbarSort;
  RxString defaultSearch = ''.obs;
  late bool enableGradientBg;

  @override
  void onInit() {
    super.onInit();
    final cachedUser = userInfoCache.get('userInfoCache');
    userLogin.value = cachedUser is UserInfoData &&
        cachedUser.isLogin == true &&
        cachedUser.mid != null;
    userInfo = userLogin.value ? cachedUser : null;
    userFace.value = userLogin.value ? cachedUser.face : '';
    hideSearchBar =
        setting.get(SettingBoxKey.hideSearchBar, defaultValue: false);
    if (setting.get(SettingBoxKey.enableSearchWord, defaultValue: true) &&
        !(Get.isRegistered<SimpleModeService>() &&
            SimpleModeService.instance.enabled.value)) {
      // 极简模式关闭搜索栏搜索词推荐
      searchDefault();
    }
    enableGradientBg =
        setting.get(SettingBoxKey.enableGradientBg, defaultValue: true);
    // 进行tabs配置
    setTabConfig();
  }

  void onRefresh() {
    int index = tabController.index;
    var ctr = tabsCtrList[index];
    final c = ctr();
    // 极简模式收藏夹 tab 无 onRefresh，忽略即可（页面自身有下拉刷新）
    c.onRefresh?.call();
  }

  void animateToTop() {
    int index = tabController.index;
    var ctr = tabsCtrList[index];
    final c = ctr();
    c.animateToTop?.call();
  }

  void updateLoginStatus(bool val) {
    final cachedUser = userInfoCache.get('userInfoCache');
    final validUser = cachedUser is UserInfoData &&
        cachedUser.isLogin == true &&
        cachedUser.mid != null;
    userLogin.value = val && validUser;
    userInfo = userLogin.value ? cachedUser : null;
    userFace.value = userLogin.value ? cachedUser.face : '';
  }

  void setTabConfig() async {
    // 极简模式：首页仅显示收藏夹（点进可查看收藏内容）
    if (Get.isRegistered<SimpleModeService>() &&
        SimpleModeService.instance.enabled.value) {
      tabs.value = [
        {
          'icon': const Icon(Icons.star_border, size: 15),
          'label': '收藏夹',
          'type': TabType.rcmd,
          'ctr': () => null,
          'page': const SimpleFavPage(),
        }
      ];
      initialIndex.value = 0;
      tabsCtrList = tabs.map((e) => e['ctr']).toList();
      tabsPageList = tabs.map<Widget>((e) => e['page']).toList();
      tabController = TabController(
        initialIndex: 0,
        length: tabs.length,
        vsync: this,
      );
      return;
    }
    defaultTabs = [...tabsConfig];
    tabbarSort = settingStorage.get(SettingBoxKey.tabbarSort,
        defaultValue: ['live', 'rcmd', 'hot', 'bangumi']);
    defaultTabs.retainWhere(
        (item) => tabbarSort.contains((item['type'] as TabType).id));
    defaultTabs.sort((a, b) => tabbarSort
        .indexOf((a['type'] as TabType).id)
        .compareTo(tabbarSort.indexOf((b['type'] as TabType).id)));

    tabs.value = defaultTabs;

    if (tabbarSort.contains(TabType.rcmd.id)) {
      initialIndex.value = tabbarSort.indexOf(TabType.rcmd.id);
    } else {
      initialIndex.value = 0;
    }
    tabsCtrList = tabs.map((e) => e['ctr']).toList();
    tabsPageList = tabs.map<Widget>((e) => e['page']).toList();

    tabController = TabController(
      initialIndex: initialIndex.value,
      length: tabs.length,
      vsync: this,
    );
    // 监听 tabController 切换
    if (enableGradientBg) {
      tabController.animation!.addListener(() {
        if (tabController.indexIsChanging) {
          if (initialIndex.value != tabController.index) {
            initialIndex.value = tabController.index;
          }
        } else {
          final int temp = tabController.animation!.value.round();
          if (initialIndex.value != temp) {
            initialIndex.value = temp;
            tabController.index = initialIndex.value;
          }
        }
      });
    }
  }

  void searchDefault() async {
    var res = await Request().get(Api.searchDefault);
    if (res.data['code'] == 0) {
      defaultSearch.value = res.data['data']['name'];
    }
  }

  @override
  void onClose() {
    searchBarStream.close();
    super.onClose();
  }
}
