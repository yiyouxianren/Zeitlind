import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/common/search_type.dart';
import 'package:pilipala/models/model_hot_video_item.dart';
import 'package:pilipala/models/video/play/url.dart';
import 'package:pilipala/models/video_detail_res.dart';
import 'package:pilipala/pages/bangumi/introduction/controller.dart';
import 'package:pilipala/pages/video/detail/controller.dart';
import 'package:pilipala/pages/video/detail/introduction/controller.dart';
import 'package:pilipala/plugin/pl_player/models/data_status.dart';
import 'package:pilipala/utils/id_utils.dart';

/// A model-independent target used by audio-only previous/next navigation.
class AudioNavigationTarget {
  const AudioNavigationTarget({
    required this.bvid,
    required this.cid,
    this.aid,
    this.cover,
  });

  final String bvid;
  final int cid;
  final int? aid;
  final String? cover;

  bool get isPlayable => bvid.isNotEmpty && cid > 0;

  bool matches(String currentBvid, int currentCid) =>
      bvid == currentBvid && cid == currentCid;
}

/// Finds the nearest playable item in [direction] without wrapping.
///
/// [direction] is normalized to -1 (previous) or 1 (next). Returns `null`
/// when the current item is unknown, the direction is zero, or the boundary
/// has been reached. Invalid entries are skipped.
AudioNavigationTarget? adjacentAudioTarget(
  List<AudioNavigationTarget> items, {
  required String currentBvid,
  required int currentCid,
  required int direction,
}) {
  if (items.isEmpty || direction == 0) return null;

  final currentIndex = items.indexWhere(
    (item) => item.matches(currentBvid, currentCid),
  );
  if (currentIndex < 0) return null;

  final step = direction < 0 ? -1 : 1;
  for (var index = currentIndex + step;
      index >= 0 && index < items.length;
      index += step) {
    if (items[index].isPlayable) return items[index];
  }
  return null;
}

/// Per-detail-page navigation state. No global queue or route changes.
class AudioNavigator {
  final List<AudioNavigationTarget> _history = [];

  List<AudioNavigationTarget>? _collection(VideoDetailController controller) {
    if (controller.videoType == SearchType.media_bangumi) {
      final intro = Get.find<BangumiIntroController>(tag: controller.heroTag);
      return (intro.bangumiDetail.value.episodes ?? [])
          .map((episode) => AudioNavigationTarget(
                bvid: episode.bvid ?? '',
                cid: episode.isViewHide == true ? -1 : (episode.cid ?? -1),
                aid: episode.aid,
                cover: episode.cover,
              ))
          .toList();
    }
    final intro = Get.find<VideoIntroController>(tag: controller.heroTag);
    final detail = intro.videoDetail.value;
    // Never navigate an old introduction while a different video is loading.
    if (detail.bvid != controller.bvid) {
      throw StateError('视频信息加载中，请稍后重试');
    }
    if (detail.ugcSeason != null) {
      return [
        for (final section in detail.ugcSeason!.sections ?? <SectionItem>[])
          for (final episode in section.episodes ?? <EpisodeItem>[])
            AudioNavigationTarget(
              bvid: episode.bvid ?? '',
              cid: episode.cid ?? episode.page?.cid ?? -1,
              aid: episode.aid,
              cover: episode.cover,
            ),
      ];
    }
    if ((detail.pages?.length ?? 0) > 1) {
      return [
        for (final page in detail.pages!)
          AudioNavigationTarget(
            bvid: controller.bvid,
            cid: page.cid ?? -1,
            aid: detail.aid,
            cover: page.cover?.isNotEmpty == true ? page.cover : detail.pic,
          ),
      ];
    }
    return null;
  }

  Future<AudioNavigationTarget?> _recommendation(
    VideoDetailController controller,
    bool Function() isCurrent,
  ) async {
    final response = await VideoHttp.relatedVideoList(bvid: controller.bvid);
    if (!isCurrent()) return null;
    if (response['status'] != true) {
      throw StateError('相关推荐加载失败，请重试');
    }
    final seen = {controller.bvid, ..._history.map((item) => item.bvid)};
    for (final item
        in (response['data'] as List).cast<HotVideoItemModel>().take(10)) {
      final bvid = item.bvid;
      if (bvid == null ||
          bvid.isEmpty ||
          !seen.add(bvid) ||
          (item.state != null && item.state! < 0) ||
          item.isOgv == true) {
        continue;
      }
      try {
        var cid = item.cid;
        if (cid == null || cid <= 0) {
          final result = await VideoHttp.videoIntro(bvid: bvid);
          if (!isCurrent()) return null;
          if (result['status'] != true) continue;
          final detail = result['data'] as VideoDetailData;
          if ((detail.state ?? 0) < 0 || detail.epId != null) continue;
          cid = detail.cid;
          if (cid == null || cid <= 0) {
            for (final page in detail.pages ?? <Part>[]) {
              if ((page.cid ?? 0) > 0) {
                cid = page.cid;
                break;
              }
            }
          }
        }
        if (cid == null || cid <= 0) continue;
        // A valid CID alone does not imply playable independent audio.
        final source = await VideoHttp.videoUrl(bvid: bvid, cid: cid);
        if (!isCurrent()) return null;
        if (source['status'] != true) continue;
        final data = source['data'] as PlayUrlModel;
        if (data.durl != null ||
            !(data.dash?.audio ?? <AudioItem>[]).any((audio) =>
                (audio.baseUrl?.isNotEmpty ?? false) ||
                (audio.backupUrl?.isNotEmpty ?? false))) {
          continue;
        }
        return AudioNavigationTarget(
          bvid: bvid,
          cid: cid,
          aid: item.aid,
          cover: item.pic ?? item.cover,
        );
      } catch (_) {
        if (!isCurrent()) return null;
        // Deleted/restricted/malformed recommendations must not block others.
      }
    }
    return null;
  }

  Future<void> skip(
    VideoDetailController controller,
    int direction, {
    required Future<dynamic>? Function() sourceRequest,
    required int Function() sourceGeneration,
  }) async {
    if (!controller.audioMode ||
        direction == 0 ||
        controller.audioSwitching.value ||
        controller.isClosed) return;
    controller.audioSwitching.value = true;
    AudioNavigationTarget? target;
    int? switchGeneration;
    var didSwitch = false;
    try {
      // Also wait for an initial source request before accepting navigation.
      await sourceRequest();
      if (controller.isClosed) return;
      final origin = AudioNavigationTarget(
        bvid: controller.bvid,
        cid: controller.cid.value,
        aid: controller.oid.value,
        cover: controller.cover.value,
      );
      final generation = sourceGeneration();
      bool isCurrent() =>
          !controller.isClosed &&
          generation == sourceGeneration() &&
          origin.matches(controller.bvid, controller.cid.value);
      final collection = _collection(controller);
      var fromHistory = false;
      if (collection != null) {
        target = adjacentAudioTarget(collection,
            currentBvid: origin.bvid,
            currentCid: origin.cid,
            direction: direction);
      } else if (direction < 0) {
        fromHistory = true;
        if (_history.isNotEmpty) target = _history.last;
      } else {
        target = await _recommendation(controller, isCurrent);
      }
      if (!isCurrent()) return;
      if (target == null) {
        SmartDialog.showToast(direction < 0
            ? '已经是第一集'
            : collection != null
                ? '已经是最后一集'
                : '暂无可播放的推荐音频');
        return;
      }
      await controller.plPlayerController.pause(notify: false);
      if (!isCurrent()) return;
      controller.audioError.value = '';
      controller.plPlayerController.isBuffering.value = false;
      controller.plPlayerController.buffered.value = Duration.zero;
      controller.subtitles = [];
      controller.clearSubtitleContent();
      controller.autoPlay.value = true;
      controller.isFirstTime = false;
      final selected = target;
      didSwitch = true;
      Future change;
      if (controller.videoType == SearchType.media_bangumi) {
        final intro = Get.find<BangumiIntroController>(tag: controller.heroTag);
        intro.bvid = selected.bvid;
        for (final episode in intro.bangumiDetail.value.episodes ?? []) {
          if (episode.cid == selected.cid && episode.bvid == selected.bvid) {
            intro.epId = episode.id;
            break;
          }
        }
        change = intro.changeSeasonOrbangu(selected.bvid, selected.cid,
            selected.aid ?? IdUtils.bv2av(selected.bvid), selected.cover ?? '');
      } else {
        // Media-list switching is also safe without an open bottom sheet.
        change = controller.changeMediaList(selected.bvid, selected.cid,
            selected.aid ?? IdUtils.bv2av(selected.bvid), selected.cover ?? '');
      }
      switchGeneration = sourceGeneration();
      // Existing switch APIs do not await queryVideoUrl. Wait for both metadata
      // and the source future captured synchronously by that API.
      final results = await Future.wait<dynamic>([
        change,
        sourceRequest() ?? Future.value(null),
      ]);
      if (controller.isClosed ||
          switchGeneration != sourceGeneration() ||
          !selected.matches(controller.bvid, controller.cid.value)) return;
      final result = results[1];
      if (result == null ||
          result['status'] != true ||
          controller.plPlayerController.dataStatus.status.value ==
              DataStatus.error) {
        throw StateError(controller.audioError.value.isNotEmpty
            ? controller.audioError.value
            : (result?['msg']?.toString() ?? '音频加载失败'));
      }
      if (fromHistory) {
        _history.removeLast();
      } else {
        _history.add(origin);
      }
    } catch (error) {
      if (!controller.isClosed &&
          (switchGeneration == null ||
              switchGeneration == sourceGeneration())) {
        final message =
            error is StateError ? error.message.toString() : '音频切换失败，请重试';
        if (didSwitch) controller.audioError.value = message;
        SmartDialog.showToast(message);
      }
    } finally {
      if (!controller.isClosed) {
        if (didSwitch && switchGeneration == sourceGeneration()) {
          controller.plPlayerController.isBuffering.value = false;
        }
        controller.audioSwitching.value = false;
      }
    }
  }
}
