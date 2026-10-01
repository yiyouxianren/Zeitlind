import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/utils/keyword_filter.dart';

void main() {
  group('KeywordFilter', () {
    test('matches literal text in video fields', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '这是一个测试[1]',
          description: '简介',
          tags: '科技',
          enabledOverride: true,
          literalOverride: const ['测试[1]'],
          regexOverride: const [],
          blacklistNameOverride: false,
        ),
        isTrue,
      );
    });

    test('literal keywords are not treated as regular expressions', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '测试1',
          enabledOverride: true,
          literalOverride: const ['测试[1]'],
          regexOverride: const [],
          blacklistNameOverride: false,
        ),
        isFalse,
      );
    });

    test('matches valid regex and ignores invalid regex', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '危险内容',
          enabledOverride: true,
          literalOverride: const [],
          regexOverride: const [r'危险.*'],
          blacklistNameOverride: false,
        ),
        isTrue,
      );
      expect(
        KeywordFilter.shouldBlock(
          title: '普通内容',
          enabledOverride: true,
          literalOverride: const [],
          regexOverride: const ['['],
          blacklistNameOverride: false,
        ),
        isFalse,
      );
    });

    test('matches blacklist username only when enabled', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '某用户的新视频',
          enabledOverride: true,
          literalOverride: const [],
          regexOverride: const [],
          blacklistNameOverride: true,
          blacklistNamesOverride: const ['某用户'],
        ),
        isTrue,
      );
      expect(
        KeywordFilter.shouldBlock(
          title: '某用户的新视频',
          enabledOverride: true,
          literalOverride: const [],
          regexOverride: const [],
          blacklistNameOverride: false,
          blacklistNamesOverride: const ['某用户'],
        ),
        isFalse,
      );
    });

    test('does not use blacklist names when the global filter is disabled', () {
      expect(
        KeywordFilter.shouldBlock(
          ownerName: '某用户',
          enabledOverride: false,
          literalOverride: const [],
          regexOverride: const [],
          blacklistNameOverride: true,
          blacklistNamesOverride: const ['某用户'],
        ),
        isFalse,
      );
    });

    test('matches blacklist names in the author field', () {
      expect(
        KeywordFilter.shouldBlock(
          ownerName: '某用户',
          enabledOverride: true,
          literalOverride: const [],
          regexOverride: const [],
          blacklistNameOverride: true,
          blacklistNamesOverride: const ['某用户'],
        ),
        isTrue,
      );
    });

    test('ignores empty blacklist names', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '普通视频',
          ownerName: '作者',
          enabledOverride: true,
          literalOverride: const [],
          regexOverride: const [],
          blacklistNameOverride: true,
          blacklistNamesOverride: const ['', '  '],
        ),
        isFalse,
      );
    });

    test('manual literals still work when blacklist names are disabled', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '命中手工词',
          ownerName: '某用户',
          enabledOverride: true,
          literalOverride: const ['手工词'],
          regexOverride: const [],
          blacklistNameOverride: false,
          blacklistNamesOverride: const ['某用户'],
        ),
        isTrue,
      );
    });

    test('followed scope blocks collection names independently', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '屏蔽合集名称',
          enabledOverride: true,
          literalOverride: const ['合集名称'],
          regexOverride: const [],
          blacklistNameOverride: false,
        ),
        isTrue,
      );
    });

    test('collection description alone does not hide the collection', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '正常合集',
          description: '描述中的关键词',
          enabledOverride: true,
          literalOverride: const ['关键词'],
          regexOverride: const [],
          blacklistNameOverride: false,
        ),
        isTrue,
      );
    });

    test('scope override works when the global setting is disabled', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '关注动态命中词',
          enabledOverride: true,
          literalOverride: const ['命中词'],
          regexOverride: const [],
          blacklistNameOverride: false,
        ),
        isTrue,
      );
    });

    test('disabled filter keeps all content', () {
      expect(
        KeywordFilter.shouldBlock(
          title: '命中词',
          enabledOverride: false,
          literalOverride: const ['命中词'],
          regexOverride: const [r'命中词'],
        ),
        isFalse,
      );
    });
  });
}
