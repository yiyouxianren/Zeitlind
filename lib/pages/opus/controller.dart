import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/read.dart';
import 'package:pilipala/http/reply.dart';
import 'package:pilipala/models/read/opus.dart';
import 'package:pilipala/models/video/reply/item.dart';
import 'package:pilipala/utils/reply_filter.dart';
import 'package:pilipala/plugin/pl_gallery/hero_dialog_route.dart';
import 'package:pilipala/plugin/pl_gallery/interactiveviewer_gallery.dart';

class OpusController extends GetxController {
  late String url;
  final RxString title = ''.obs;
  late String id;
  late String articleType;
  String? commentId;
  int commentType = 11;
  bool commentsLoading = false;
  bool commentsLoaded = false;
  final Rx<OpusDataModel> opusData = OpusDataModel().obs;
  final RxList<ReplyItemModel> replies = <ReplyItemModel>[].obs;
  final ScrollController scrollController = ScrollController();
  final StreamController<bool> appbarStream =
      StreamController<bool>.broadcast();
  int replyPage = 0;
  bool replyHasMore = true;
  String replyMessage = '';

  @override
  void onInit() {
    super.onInit();
    title.value = Get.parameters['title'] ?? '';
    id = Get.parameters['id'] ?? '';
    articleType = Get.parameters['articleType'] ?? 'opus';
    url = 'https://www.bilibili.com/opus/$id';
    scrollController.addListener(_scrollListener);
  }

  Future<Map<String, dynamic>> fetchOpusData() async {
    final res = await ReadHttp.parseArticleOpus(id: id);
    if (res['status']) {
      final data = res['data'];
      final basic = data is OpusDataModel ? data.detail?.basic : null;
      if (data is! OpusDataModel || data.detail == null || basic == null) {
        return {
          ...res,
          'status': false,
          'msg': res['msg'] ?? '专栏内容为空',
        };
      }
      title.value = basic.title ?? title.value;
      opusData.value = data;
      commentId = basic.commentIdStr ?? basic.ridStr;
      commentType = basic.commentType ?? 11;
      await loadReplies(refresh: true);
    }
    return res;
  }

  Future<void> loadReplies({bool refresh = false}) async {
    final oid = int.tryParse(commentId ?? '');
    if (oid == null || commentsLoading || (!replyHasMore && !refresh)) return;
    commentsLoading = true;
    if (refresh) {
      replyPage = 0;
      replyHasMore = true;
      replyMessage = '';
      replies.clear();
    }
    update();
    try {
      final res = await ReplyHttp.replyList(
        oid: oid,
        pageNum: replyPage + 1,
        type: commentType > 0 ? commentType : 11,
        sort: 1,
      );
      if (res['status']) {
        final data = res['data'];
        final List<ReplyItemModel> pageItems =
            ReplyFilter.filterList(data.replies);
        final existing = replies.map((item) => item.rpid).toSet();
        replies
            .addAll(pageItems.where((item) => !existing.contains(item.rpid)));
        replyPage++;
        replyHasMore = pageItems.length >= 20;
        replyMessage = pageItems.isEmpty ? '没有更多评论' : '';
      } else {
        replyMessage = res['msg']?.toString() ?? '评论加载失败';
      }
    } catch (_) {
      replyMessage = '评论加载失败';
    } finally {
      commentsLoading = false;
      commentsLoaded = true;
      update();
    }
  }

  void onScroll() {
    if (!scrollController.hasClients) return;
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 300) {
      loadReplies();
    }
  }

  void _scrollListener() {
    if (!scrollController.hasClients || appbarStream.isClosed) return;
    appbarStream.add(scrollController.position.pixels > 100);
  }

  void onPreviewImg(List<String> picList, int initIndex, BuildContext context) {
    if (picList.isEmpty || initIndex < 0 || initIndex >= picList.length) return;
    Navigator.of(context).push(
      HeroDialogRoute<void>(
        builder: (_) => InteractiveviewerGallery(
          sources: picList,
          initIndex: initIndex,
          onPageChanged: (_) {},
        ),
      ),
    );
  }

  void onJumpWebview() {
    Get.toNamed('/webview', parameters: {
      'url': url,
      'type': 'webview',
      'pageTitle': title.value,
    });
  }

  @override
  void onClose() {
    scrollController.removeListener(_scrollListener);
    scrollController.dispose();
    appbarStream.close();
    super.onClose();
  }
}
