import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/utils/blacklist_filter.dart';

void main() {
  group('BlacklistFilter', () {
    const blackMids = <int>{42, 99};

    test('filters numeric and string mids when enabled', () {
      final result = BlacklistFilter.filter<Map<String, dynamic>>(
        [
          {'mid': 42},
          {'mid': '99'},
          {'mid': 7},
        ],
        (item) => item['mid'],
        enabledOverride: true,
        blackMidsOverride: blackMids,
      );

      expect(result, hasLength(1));
      expect(result.single['mid'], 7);
    });

    test('keeps blacklisted videos when disabled', () {
      final result = BlacklistFilter.filter<int>(
        [42, 7],
        (mid) => mid,
        enabledOverride: false,
        blackMidsOverride: blackMids,
      );

      expect(result, [42, 7]);
    });

    test('does not block missing mids', () {
      expect(
        BlacklistFilter.isBlocked(
          null,
          enabledOverride: true,
          blackMidsOverride: blackMids,
        ),
        isFalse,
      );
    });
  });
}
