import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/models/video/play/quality.dart';
import 'package:pilipala/models/video/play/url.dart';
import 'package:pilipala/pages/common/timer_close.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/plugin/pl_player/models/play_repeat.dart';
import '../controller.dart';
import 'audio_time_jump_dialog.dart';

class AudioPlayerPanel extends StatefulWidget {
  const AudioPlayerPanel({super.key, required this.controller});
  final VideoDetailController controller;

  @override
  State<AudioPlayerPanel> createState() => _AudioPlayerPanelState();
}

class _AudioPlayerPanelState extends State<AudioPlayerPanel> {
  VideoDetailController get controller => widget.controller;

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
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 2,
                      children: [
                        _panelButton(
                          icon: Icons.more_time_rounded,
                          label: '时间跳转',
                          onPressed: duration > Duration.zero &&
                                  !controller.audioSwitching.value
                              ? () => _jumpToTime(context, player)
                              : null,
                        ),
                        _panelButton(
                          icon: Icons.album_outlined,
                          label: controller.currentAudioQa?.description ?? '音质',
                          onPressed: () => _audioQualitySheet(context, player),
                        ),
                        _panelButton(
                          icon: Icons.repeat,
                          label: player.playRepeat.description,
                          onPressed: () => _repeatSheet(context, player),
                        ),
                        _panelButton(
                          icon: null,
                          label: '${player.playbackSpeed}x',
                          onPressed: () => _speedSheet(context, player),
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

  /// 音频面板底部功能按钮（统一白字样式）
  Widget _panelButton({
    IconData? icon,
    required String label,
    VoidCallback? onPressed,
  }) {
    const style = TextStyle(color: Colors.white, fontSize: 12);
    final child = Text(label, style: style);
    return icon == null
        ? TextButton(onPressed: onPressed, child: child)
        : TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 16, color: Colors.white),
            label: child,
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

  /// 选择音质（音频模式）
  void _audioQualitySheet(BuildContext context, PlPlayerController player) {
    final List<Map<String, dynamic>> options = _audioOptions();
    if (options.isEmpty) {
      SmartDialog.showToast('当前视频没有可切换的音质');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      elevation: 0,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          width: double.infinity,
          height: 250,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          margin: const EdgeInsets.all(12),
          child: Column(
            children: [
              const SizedBox(
                height: 45,
                child: Center(child: Text('选择音质')),
              ),
              Expanded(
                child: Material(
                  child: ListView(
                    children: [
                      for (final option in options)
                        ListTile(
                          onTap: () {
                            if (controller.currentAudioQa?.code ==
                                option['id']) {
                              Get.back();
                              return;
                            }
                            controller.currentAudioQa =
                                AudioQualityCode.fromCode(option['id'] as int);
                            controller.updatePlayer();
                            Get.back();
                            setState(() {});
                          },
                          dense: true,
                          contentPadding:
                              const EdgeInsets.only(left: 20, right: 20),
                          title: Text(option['label'].toString()),
                          subtitle: Text(
                            option['codec'].toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.outline,
                            ),
                          ),
                          trailing: controller.currentAudioQa?.code ==
                                  option['id']
                              ? Icon(
                                  Icons.done,
                                  color: Theme.of(ctx).colorScheme.primary,
                                )
                              : const SizedBox(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 当前视频可选的音质列表（含杜比 / 无损）
  List<Map<String, dynamic>> _audioOptions() {
    final List<Map<String, dynamic>> options = [];
    final Set<int> seen = <int>{};
    void add(AudioItem? item) {
      final int? id = item?.id;
      if (id == null || !seen.add(id)) return;
      options.add({
        'id': id,
        'label': AudioQualityCode.fromCode(id)?.description ??
            item?.quality?.toString() ??
            '$id',
        'codec': item?.codecs?.toString() ?? '',
      });
    }

    try {
      final dash = controller.data.dash;
      if (dash == null) return options;
      add(dash.flac?.audio);
      for (final item in dash.dolby?.audio ?? const <AudioItem>[]) {
        add(item);
      }
      for (final item in dash.audio ?? const <AudioItem>[]) {
        add(item);
      }
    } catch (_) {
      // 数据未就绪（例如刚切集），返回已有选项
    }
    return options;
  }

  /// 选择播放顺序（音频模式）
  void _repeatSheet(BuildContext context, PlPlayerController player) {
    showModalBottomSheet<void>(
      context: context,
      elevation: 0,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          width: double.infinity,
          height: 250,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          margin: const EdgeInsets.all(12),
          child: Column(
            children: [
              const SizedBox(
                height: 45,
                child: Center(child: Text('选择播放顺序')),
              ),
              Expanded(
                child: Material(
                  child: ListView(
                    children: [
                      for (final PlayRepeat i in PlayRepeat.values)
                        ListTile(
                          onTap: () {
                            player.setPlayRepeat(i);
                            Get.back();
                            setState(() {});
                          },
                          dense: true,
                          contentPadding:
                              const EdgeInsets.only(left: 20, right: 20),
                          title: Text(i.description),
                          trailing: player.playRepeat == i
                              ? Icon(
                                  Icons.done,
                                  color: Theme.of(ctx).colorScheme.primary,
                                )
                              : const SizedBox(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                      setState(() {});
                    }),
            ]));
  }
}
