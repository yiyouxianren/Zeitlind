import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/utils/audio_navigation.dart';

void main() {
  const items = [
    AudioNavigationTarget(bvid: 'a', cid: 1),
    AudioNavigationTarget(bvid: 'bad', cid: -1),
    AudioNavigationTarget(bvid: 'a', cid: 2),
    AudioNavigationTarget(bvid: 'b', cid: 3),
  ];
  AudioNavigationTarget? adjacent(String bvid, int cid, int direction) =>
      adjacentAudioTarget(items,
          currentBvid: bvid, currentCid: cid, direction: direction);

  test('next and previous skip invalid collection entries', () {
    expect(adjacent('a', 1, 1)?.cid, 2);
    expect(adjacent('a', 2, -1)?.cid, 1);
    expect(adjacent('a', 2, 1)?.bvid, 'b');
  });
  test('first and last entries stop at boundaries', () {
    expect(adjacent('a', 1, -1), isNull);
    expect(adjacent('b', 3, 1), isNull);
  });
  test('unknown, empty and zero direction cannot navigate', () {
    expect(adjacent('unknown', 1, 1), isNull);
    expect(adjacent('a', 1, 0), isNull);
    expect(
        adjacentAudioTarget([], currentBvid: 'a', currentCid: 1, direction: 1),
        isNull);
  });
  test('identity includes CID for multipart videos', () {
    expect(items.first.matches('a', 1), isTrue);
    expect(items.first.matches('a', 2), isFalse);
    expect(const AudioNavigationTarget(bvid: '', cid: 4).isPlayable, isFalse);
  });
}
