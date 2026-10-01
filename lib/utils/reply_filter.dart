import 'package:pilipala/models/video/reply/item.dart';
import 'package:pilipala/utils/blacklist_filter.dart';
import 'package:pilipala/utils/keyword_filter.dart';

class ReplyFilter {
  const ReplyFilter._();

  static List<ReplyItemModel> filterList(Iterable<ReplyItemModel>? items) {
    return (items ?? const <ReplyItemModel>[])
        .where((item) => !shouldBlock(item))
        .map(_filterNested)
        .toList();
  }

  static bool shouldBlock(ReplyItemModel item) {
    if (BlacklistFilter.isBlocked(item.mid ?? item.member?.mid)) {
      return true;
    }
    return KeywordFilter.shouldBlock(
      title: item.content?.message,
      ownerName: item.member?.uname,
    );
  }

  static ReplyItemModel _filterNested(ReplyItemModel item) {
    item.replies = filterList(item.replies?.whereType<ReplyItemModel>());
    return item;
  }
}
