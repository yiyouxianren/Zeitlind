import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/view_point_segment_progress_bar.dart';
import 'package:pilipala/models/video_detail_res.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/utils/feed_back.dart';

class BottomControl extends StatelessWidget implements PreferredSizeWidget {
  final PlPlayerController? controller;
  final Function? triggerFullScreen;
  final List<Widget>? buildBottomControl;
  final List<VideoViewPoint> viewPoints;
  final bool showViewPointBar;
  final Function(Duration)? onSeekViewPoint;
  const BottomControl({
    this.controller,
    this.triggerFullScreen,
    this.buildBottomControl,
    this.viewPoints = const <VideoViewPoint>[],
    this.showViewPointBar = true,
    this.onSeekViewPoint,
    Key? key,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size(double.infinity, kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    Color colorTheme = Theme.of(context).colorScheme.primary;
    final _ = controller!;
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.only(left: 18, right: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Obx(() {
            final int value = _.sliderPositionSeconds.value;
            final int max = _.durationSeconds.value;
            final int buffer = _.bufferedSeconds.value;
            final hasSegments = viewPoints
                .any((point) => point.to != null && point.to! > 0 && max > 0);
            return Padding(
              padding: const EdgeInsets.only(left: 7, right: 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value <= max && max > 0)
                    Stack(
                      children: [
                        ProgressBar(
                          progress: Duration(seconds: value),
                          buffered: Duration(seconds: buffer),
                          total: Duration(seconds: max),
                          progressBarColor: colorTheme,
                          baseBarColor: Colors.white.withOpacity(0.2),
                          bufferedBarColor: colorTheme.withOpacity(0.4),
                          timeLabelLocation: TimeLabelLocation.none,
                          thumbColor: colorTheme,
                          barHeight: 3.5,
                          thumbRadius: 7,
                          onDragStart: (duration) {
                            feedBack();
                            _.onChangedSliderStart();
                          },
                          onDragUpdate: (duration) {
                            _.onUpdatedSliderProgress(duration.timeStamp);
                          },
                          onSeek: (duration) {
                            _.onChangedSliderEnd();
                            _.onChangedSlider(duration.inSeconds.toDouble());
                            _.seekTo(Duration(seconds: duration.inSeconds),
                                type: 'slider');
                          },
                        ),
                      ],
                    ),
                  if (hasSegments)
                    Obx(() {
                      if (!_.showControls.value) return const SizedBox.shrink();
                      if (!showViewPointBar) return const SizedBox.shrink();
                      final segments = viewPoints
                          .where((point) =>
                              point.to != null && point.to! > 0 && max > 0)
                          .map((point) => ViewPointSegment(
                                end: (point.to! / max).clamp(0.0, 1.0),
                                title: point.content,
                                url: point.imgUrl,
                                from: point.from,
                                to: point.to,
                              ))
                          .toList();
                      return Padding(
                        padding: const EdgeInsets.only(top: 3, bottom: 6),
                        child: SizedBox(
                          width: double.infinity,
                          child: ViewPointSegmentProgressBar(
                            segments: segments,
                            onSeek: onSeekViewPoint,
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          }),
          Row(children: [...buildBottomControl!]),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
