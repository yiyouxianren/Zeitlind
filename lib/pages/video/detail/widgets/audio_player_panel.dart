import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/pages/common/timer_close.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import '../controller.dart';
import 'audio_time_jump_dialog.dart';

class AudioPlayerPanel extends StatelessWidget {
  const AudioPlayerPanel({super.key, required this.controller});
  final VideoDetailController controller;

  String _time(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = controller.plPlayerController;
    final screenSize = MediaQuery.sizeOf(context);
    final coverWidth = screenSize.width;
    // Keep the artwork square and let BoxFit.cover crop the longer side.
    final coverHeight = coverWidth;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Obx(() {
        final position = player.position.value;
        final duration = player.duration.value;
        final max = duration.inMilliseconds > 0
            ? duration.inMilliseconds.toDouble()
            : 1.0;
        return SizedBox(
          width: coverWidth,
          height: coverHeight,
          child: Stack(fit: StackFit.expand, children: [
            NetworkImgLayer(
                src: controller.cover.value,
                width: coverWidth,
                height: coverHeight,
                type: 'emote'),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
            // 定时关闭入口：右上角（音频模式）
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: TimerCloseButton(color: Colors.white),
              ),
            ),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '上一首',
                    iconSize: 40,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    onPressed: controller.audioSwitching.value
                        ? null
                        : () => controller.skipAudio(-1),
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    tooltip:
                        player.playerStatus.status.value == PlayerStatus.playing
                            ? '暂停'
                            : '播放',
                    iconSize: 64,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    onPressed: controller.audioSwitching.value
                        ? null
                        : () => player.playerStatus.status.value ==
                                PlayerStatus.playing
                            ? player.pause()
                            : player.play(),
                    icon: Icon(
                        player.playerStatus.status.value == PlayerStatus.playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    tooltip: '下一首',
                    iconSize: 40,
                    color: Colors.white,
                    disabledColor: Colors.white38,
                    onPressed: controller.audioSwitching.value
                        ? null
                        : () => controller.skipAudio(1),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Slider(
                        value: position.inMilliseconds.clamp(0, max).toDouble(),
                        max: max,
                        onChanged: (value) => player.seekTo(
                          Duration(milliseconds: value.round()),
                          type: 'slider',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Text(_time(position),
                            style: const TextStyle(color: Colors.white)),
                        const Spacer(),
                        Text(_time(duration),
                            style: const TextStyle(color: Colors.white)),
                      ]),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white38,
                          ),
                          onPressed: duration > Duration.zero &&
                                  !controller.audioSwitching.value
                              ? () => _jumpToTime(context, player)
                              : null,
                          icon: const Icon(Icons.more_time_rounded),
                          label: const Text('时间跳转'),
                        ),
                        TextButton(
                          onPressed: () => _speedSheet(context, player),
                          child: Text('${player.playbackSpeed}x',
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }

  Future<void> _jumpToTime(
      BuildContext context, PlPlayerController player) async {
    final cid = controller.cid.value;
    final bvid = controller.bvid;
    final target = await showDialog<Duration>(
      context: context,
      builder: (_) => AudioTimeJumpDialog(
        position: player.position.value,
        duration: player.duration.value,
      ),
    );
    if (target != null &&
        controller.cid.value == cid &&
        controller.bvid == bvid) {
      await player.seekTo(target, type: 'slider');
    }
  }

  void _speedSheet(BuildContext context, PlPlayerController player) {
    showModalBottomSheet<void>(
        context: context,
        builder: (_) => ListView(shrinkWrap: true, children: [
              for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                ListTile(
                    title: Text('${speed}x'),
                    onTap: () {
                      player.setPlaybackSpeed(speed);
                      Get.back();
                    }),
            ]));
  }
}
