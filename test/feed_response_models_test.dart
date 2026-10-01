import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/models/dynamics/result.dart';
import 'package:pilipala/models/live/follow.dart';
import 'package:pilipala/models/live/item.dart';
import 'package:pilipala/utils/dynamic_filter.dart';

void main() {
  group('dynamic response models', () {
    test('accepts missing items and terminal pagination', () {
      final model = DynamicsDataModel.fromJson({
        'has_more': false,
        'items': null,
        'offset': null,
      });

      expect(model.hasMore, false);
      expect(model.items, isEmpty);
      expect(model.offset, '');
    });

    test('skips malformed dynamic entries while keeping valid ones', () {
      final model = DynamicsDataModel.fromJson({
        'has_more': true,
        'items': [
          'invalid',
          {'id_str': '1', 'type': 'DYNAMIC_TYPE_WORD'},
        ],
      });

      expect(model.items, hasLength(1));
      expect(model.items!.single.idStr, '1');
    });

    test('blocks forwarded content when original contains a keyword', () {
      final item = DynamicItemModel.fromJson({
        'type': 'DYNAMIC_TYPE_FORWARD',
        'modules': {
          'module_dynamic': {
            'desc': {'text': '正常转发'},
          },
        },
        'orig': {
          'modules': {
            'module_dynamic': {
              'major': {
                'archive': {'title': '命中关键词'}
              },
            },
          },
        },
      });
      expect(
        DynamicFilter.shouldBlock(
          item,
          scopeEnabledOverride: true,
          literalOverride: const ['关键词'],
          regexOverride: const [],
          blacklistNameOverride: false,
        ),
        isTrue,
      );
    });

    test('parses live recommendation content from string or map', () {
      final fromString = DynamicLiveModel.fromJson({
        'content':
            '{"type":1,"live_play_info":{"room_id":42,"title":"live","watched_show":{"text_large":"1万"}}}',
      });
      final fromMap = DynamicLiveModel.fromJson({
        'content': {
          'type': 1,
          'live_play_info': {'room_id': 43, 'live_status': 1},
        },
      });

      expect(fromString.roomId, 42);
      expect(fromString.title, 'live');
      expect(fromString.watchedShow?['text_large'], '1万');
      expect(fromMap.roomId, 43);
      expect(fromMap.liveStatus, 1);
    });

    test('ignores malformed live recommendation content', () {
      final model = DynamicLiveModel.fromJson({'content': '{bad json'});

      expect(model.roomId, isNull);
      expect(model.liveStatus, isNull);
    });
  });

  group('live response models', () {
    test('uses an empty following list when list is absent or invalid', () {
      expect(LiveFollowingModel.fromJson({}).list, isEmpty);
      expect(LiveFollowingModel.fromJson({'list': null}).list, isEmpty);
      expect(LiveFollowingModel.fromJson({'list': 'invalid'}).list, isEmpty);
    });

    test('skips invalid following entries', () {
      final model = LiveFollowingModel.fromJson({
        'list': [
          null,
          'invalid',
          {'roomid': 7, 'uname': 'up', 'live_status': 1},
        ],
      });

      expect(model.list, hasLength(1));
      expect(model.list.single.roomId, 7);
      expect(model.list.single.uname, 'up');
    });

    test('parses current web live recommendation fields', () {
      final model = LiveItemModel.fromJson({
        'roomid': '42',
        'uid': '7',
        'title': 'live',
        'uname': 'up',
        'area_v2_id': 21,
        'area_v2_name': '视频唱见',
        'area_v2_parent_id': 1,
        'area_v2_parent_name': '娱乐',
        'cover': 'cover.jpg',
      });

      expect(model.roomId, 42);
      expect(model.uid, 7);
      expect(model.areaId, 21);
      expect(model.areaName, '视频唱见');
      expect(model.parentId, 1);
      expect(model.parentName, '娱乐');
      expect(model.pic, 'cover.jpg');
    });

    test('parses current followed-live fields', () {
      final item = LiveFollowingItemModel.fromJson({
        'room_id': 9,
        'nickname': 'up',
        'roomname': 'live',
        'live_status': 1,
        'area_v2_name': '手游',
        'keyframe': 'frame.jpg',
      });
      expect(item.roomId, 9);
      expect(item.uname, 'up');
      expect(item.title, 'live');
      expect(item.areaName, '手游');
      expect(item.pic, 'frame.jpg');
      expect(item.recordLiveTime, 0);
    });
  });
}
