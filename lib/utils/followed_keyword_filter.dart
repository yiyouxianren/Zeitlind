import 'package:pilipala/models/member/seasons.dart';
import 'package:pilipala/utils/keyword_filter.dart';
import 'package:pilipala/utils/storage.dart';

class FollowedKeywordFilter {
  const FollowedKeywordFilter._();

  static bool enabled() =>
      GStrorage.setting.get(
        SettingBoxKey.enableKeywordFilterForFollowed,
        defaultValue: false,
      ) ==
      true;

  static bool shouldBlockArchive(MemberArchiveItem item) {
    return KeywordFilter.shouldBlock(
      title: item.title,
      enabledOverride: enabled(),
    );
  }

  static bool shouldBlockSeason(MemberSeasonsList item) {
    final name = item.meta?.name;
    // Only the collection name can hide the entire collection. Matching a
    // video's title is handled separately by shouldBlockArchive.
    return KeywordFilter.shouldBlock(
      title: name,
      enabledOverride: enabled(),
    );
  }
}
