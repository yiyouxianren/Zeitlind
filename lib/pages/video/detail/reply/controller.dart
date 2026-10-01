import 'package:easy_debounce/easy_throttle.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/reply.dart';
import 'package:pilipala/models/common/reply_sort_type.dart';
import 'package:pilipala/models/common/reply_type.dart';
import 'package:pilipala/models/video/reply/item.dart';
import 'package:pilipala/utils/reply_filter.dart';
import 'package:pilipala/utils/feed_back.dart';
import 'package:pilipala/utils/storage.dart';

class VideoReplyController extends GetxController {
  VideoReplyController(
    this.aid,
    this.rpid,
    this.replyLevel,
  );
  // 视频aid 请求时使用的oid
  int? aid;
  // 层级 2为楼中楼
  String? replyLevel;
  // rpid 请求楼中楼回复
  String? rpid;
  RxList<ReplyItemModel> replyList = <ReplyItemModel>[].obs;
  // 当前页
  int currentPage = 0;
  bool isLoadingMore = false;
  RxString noMore = ''.obs;
  int ps = 20;
  RxInt count = 0.obs;
  // 服务端审核/排序同步前，保留本次会话刚发布的评论
  final List<ReplyItemModel> _locallySubmittedReplies = <ReplyItemModel>[];

  ReplySortType _sortType = ReplySortType.time;
  RxString sortTypeTitle = ReplySortType.time.titles.obs;
  RxString sortTypeLabel = ReplySortType.time.labels.obs;

  Box setting = GStrorage.setting;
  RxInt replyReqCode = 200.obs;

  @override
  void onInit() {
    super.onInit();
    int deaultReplySortIndex =
        setting.get(SettingBoxKey.replySortType, defaultValue: 0) as int;
    if (deaultReplySortIndex == 2) {
      setting.put(SettingBoxKey.replySortType, 0);
      deaultReplySortIndex = 0;
    }
    _sortType = ReplySortType.values[deaultReplySortIndex];
    sortTypeTitle.value = _sortType.titles;
    sortTypeLabel.value = _sortType.labels;
  }

  Future queryReplyList({type = 'init'}) async {
    if (isLoadingMore) {
      return;
    }
    isLoadingMore = true;
    if (type == 'init') {
      currentPage = 0;
      noMore.value = '';
    }
    if (noMore.value == '没有更多了') {
      isLoadingMore = false;
      return;
    }
    final res = await ReplyHttp.replyList(
      oid: aid!,
      pageNum: currentPage + 1,
      ps: ps,
      type: ReplyType.video.index,
      sort: _sortType.index,
    );
    if (res['status']) {
      final List<ReplyItemModel> replies =
          ReplyFilter.filterList(res['data'].replies);
      if (replies.isNotEmpty) {
        noMore.value = '加载中...';

        /// 第一页回复数小于请求页大小，说明没有下一页
        if (currentPage == 0 && replies.length < ps) {
          noMore.value = '没有更多了';
        }
        currentPage++;

        if (replyList.length == res['data'].page.acount) {
          noMore.value = '没有更多了';
        }
      } else {
        // 未登录状态replies可能返回null
        noMore.value = currentPage == 0 ? '还没有评论' : '没有更多了';
      }
      if (type == 'init') {
        // 添加置顶回复
        if (res['data'].upper.top != null) {
          final top = ReplyFilter.filterList([res['data'].upper.top]);
          if (top.isNotEmpty) {
            final bool flag = replies
                .any((ReplyItemModel reply) => reply.rpid == top.first.rpid);
            if (!flag) replies.insert(0, top.first);
          }
        }
        replies.insertAll(0, ReplyFilter.filterList(res['data'].topReplies));
        for (final submitted in _locallySubmittedReplies.reversed) {
          if (!ReplyFilter.shouldBlock(submitted) &&
              !replies.any((item) => item.rpid == submitted.rpid)) {
            replies.insert(0, submitted);
          }
        }
        count.value = res['data'].page.count;
        replyList.value = replies;
      } else {
        replyList.addAll(replies);
      }
    }
    replyReqCode.value = res['code'];
    isLoadingMore = false;
    return res;
  }

  // 上拉加载
  Future<void> onLoad() async {
    await queryReplyList(type: 'onLoad');
  }

  Future<void> refreshAfterSubmit(ReplyItemModel submitted) async {
    if (!_locallySubmittedReplies.any((item) => item.rpid == submitted.rpid)) {
      _locallySubmittedReplies.add(submitted);
    }
    await queryReplyList(type: 'init');
    if (!replyList.any((item) => item.rpid == submitted.rpid) &&
        !ReplyFilter.shouldBlock(submitted)) {
      replyList.insert(0, submitted);
      count.value++;
    }
  }

  // 排序搜索评论
  queryBySort() {
    EasyThrottle.throttle('queryBySort', const Duration(seconds: 1), () {
      feedBack();
      switch (_sortType) {
        case ReplySortType.time:
          _sortType = ReplySortType.like;
          break;
        case ReplySortType.like:
          _sortType = ReplySortType.time;
          break;
        default:
      }
      sortTypeTitle.value = _sortType.titles;
      sortTypeLabel.value = _sortType.labels;
      currentPage = 0;
      noMore.value = '';
      replyList.clear();
      queryReplyList(type: 'init');
    });
  }
}
