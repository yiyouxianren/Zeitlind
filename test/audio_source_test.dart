import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/models/video/play/url.dart';
import 'package:pilipala/plugin/pl_player/models/data_source.dart';
import 'package:pilipala/utils/audio_source_utils.dart';

void main() {
  test('selects preferred DASH audio without mutating arrays', () {
    final audio = [AudioItem(id: 30216, baseUrl: 'low')];
    final dash = Dash(
        audio: audio,
        dolby: Dolby(audio: [AudioItem(id: 30250, baseUrl: 'dolby')]));
    expect(selectAudioSource(dash, 30250), 'dolby');
    expect(audio.length, 1);
  });

  test('rejects DASH without supported audio', () {
    expect(() => selectAudioSource(Dash(), 30280), throwsStateError);
  });

  test('audio-only DataSource uses explicit primary source and copies flag',
      () {
    final data = DataSource(
      type: DataSourceType.network,
      audioSource: 'audio',
      audioOnly: true,
    );
    expect(data.primarySource, 'audio');
    expect(data.videoSource, isNull);
    expect(data.audioOnly, isTrue);
    final copy = data.copyWith(audioOnly: false, videoSource: 'video');
    expect(copy.audioOnly, false);
    expect(copy.primarySource, 'video');
  });
}
