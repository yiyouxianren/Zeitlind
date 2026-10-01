import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/models/search/result.dart';
import 'package:pilipala/utils/blacklist_filter.dart';

void main() {
  group('置顶 UP 卡片黑名单过滤', () {
    test('黑名单中的 UP 被过滤掉', () {
      final users = [
        SearchUserItemModel.fromJson({'mid': 1, 'uname': 'a'}),
        SearchUserItemModel.fromJson({'mid': 2, 'uname': 'b'}),
      ];
      final visible = BlacklistFilter.filter(
        users,
        (dynamic item) => item.mid,
        enabledOverride: true,
        blackMidsOverride: const [1],
      );
      expect(visible.length, 1);
      expect(visible.first.mid, 2);
    });

    test('黑名单关闭时不过滤', () {
      final users = [
        SearchUserItemModel.fromJson({'mid': 1, 'uname': 'a'}),
      ];
      final visible = BlacklistFilter.filter(
        users,
        (dynamic item) => item.mid,
        enabledOverride: false,
        blackMidsOverride: const [1],
      );
      expect(visible.length, 1);
    });
  });
}
