import 'package:pilipala/models/video/play/url.dart';
import 'package:pilipala/utils/utils.dart';

/// Selects the preferred DASH audio URL without modifying the response model.
String selectAudioSource(Dash dash, int preferredQuality) {
  final candidates = <AudioItem>[];
  candidates.addAll(dash.audio ?? const <AudioItem>[]);
  candidates.addAll(dash.dolby?.audio ?? const <AudioItem>[]);
  final flac = dash.flac?.audio;
  if (flac != null) candidates.add(flac);
  candidates.removeWhere((item) => item.id == null || item.baseUrl == null);
  if (candidates.isEmpty) {
    throw StateError('DASH response does not contain a supported audio source');
  }
  final ids = candidates.map((item) => item.id!).toList();
  var selected = Utils.findClosestNumber(preferredQuality, ids);
  if (!ids.contains(preferredQuality) &&
      ids.any((id) => id > preferredQuality)) {
    selected = 30280;
  }
  final item = candidates.firstWhere(
    (candidate) => candidate.id == selected,
    orElse: () => candidates.first,
  );
  return item.baseUrl!;
}
