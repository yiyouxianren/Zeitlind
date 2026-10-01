import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/pages/common/timer_close.dart';
import 'package:pilipala/plugin/pl_player/index.dart';

import 'controller.dart';

/// 离线音频播放页：移植音频模式控件（播放/暂停、上一首/下一首、
/// 进度条、时间跳转、倍速、定时关闭），播放本地 music 文件。
class OfflineAudioPage extends StatefulWidget {
  const OfflineAudioPage({super.key});

  @override
  State<OfflineAudioPage> createState() => _OfflineAudioPageState();
}

class _OfflineAudioPageState extends State<OfflineAudioPage> {
  late PlPlayerController plPlayerController;
  late List<OfflineVideoItem> playlist;
  int index = 0;
  bool _switching = false;

  OfflineVideoItem get item => playlist[index];

  Future<void> _open(int i) async {
    index = i;
    setState(() {});
    await plPlayerController.setDataSource(
      DataSource(file: File(item.path), type: DataSourceType.file),
      autoplay: true,
      bvid: '',
      cid: 0,
      enableHeart: false,
    );
  }

  @override
  void initState() {
    super.initState();
    final dynamic args = Get.arguments;
    final OfflineVideoItem current = args['item'] as OfflineVideoItem;
    final List<OfflineVideoItem> all =
        (args['all'] as List<OfflineVideoItem>?) ?? <OfflineVideoItem>[];
    playlist = <OfflineVideoItem>[
      current,
      ...all.where((e) => e.path != current.path),
    ];
    plPlayerController = PlPlayerController(videoType: 'archive');
    _open(0);
  }

  @override
  void dispose() {
    plPlayerController.dispose();
    super.dispose();
  }

  Future<void> _skip(int delta) async {
    if (_switching || playlist.length < 2) return;
    _switching = true;
    try {
      final int next = (index + delta + playlist.length) % playlist.length;
      await _open(next);
    } finally {
      _switching = false;
    }
  }

  String _time(Duration value) {
    final seconds = value.inSeconds;
    if (seconds >= 3600) {
      return '${(seconds ~/ 3600)}:'
          '${(seconds % 3600 ~/ 60).toString().padLeft(2, '0')}:'
          '${(seconds % 60).toString().padLeft(2, '0')}';
    }
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = plPlayerController;
    final screenSize = MediaQuery.sizeOf(context);
    final coverWidth = screenSize.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: coverWidth,
        height: screenSize.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 本地音频无网络封面：音乐底色背景
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF303F60), Color(0xFF101828)],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
            // 定时关闭入口：右上角（对齐音频模式）
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: TimerCloseButton(color: Colors.white),
              ),
            ),
            // 返回按钮
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                bottom: false,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Get.back(),
                ),
              ),
            ),
            // 标题
            Positioned(
              top: 0,
              left: 56,
              right: 56,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_note_rounded,
                      size: 120, color: Colors.white24),
                  const SizedBox(height: 24),
                  // 播放控制（移植音频模式布局）
                  Obx(
                    () => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '上一首',
                          iconSize: 40,
                          color: Colors.white,
                          disabledColor: Colors.white38,
                          onPressed: _switching ? null : () => _skip(-1),
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          tooltip:
                              player.playerStatus.status.value ==
                                      PlayerStatus.playing
                                  ? '暂停'
                                  : '播放',
                          iconSize: 64,
                          color: Colors.white,
                          disabledColor: Colors.white38,
                          onPressed: _switching
                              ? null
                              : () => player.playerStatus.status.value ==
                                      PlayerStatus.playing
                                  ? player.pause()
                                  : player.play(),
                          icon: Icon(
                            player.playerStatus.status.value ==
                                    PlayerStatus.playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                          ),
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          tooltip: '下一首',
                          iconSize: 40,
                          color: Colors.white,
                          disabledColor: Colors.white38,
                          onPressed: _switching ? null : () => _skip(1),
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
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
                child: Obx(
                  () {
                    final position = player.position.value;
                    final duration = player.duration.value;
                    final double max = duration.inMilliseconds > 0
                        ? duration.inMilliseconds.toDouble()
                        : 1.0;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Slider(
                            value: position.inMilliseconds
                                .clamp(0, max.toInt())
                                .toDouble(),
                            max: max,
                            onChanged: (value) => player.seekTo(
                              Duration(milliseconds: value.round()),
                              type: 'slider',
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(_time(position),
                                  style: const TextStyle(color: Colors.white)),
                              const Spacer(),
                              Text(_time(duration),
                                  style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white38,
                              ),
                              onPressed: duration > Duration.zero
                                  ? () => _jumpToTime(context, player)
                                  : null,
                              icon: const Icon(Icons.more_time_rounded),
                              label: const Text('时间跳转'),
                            ),
                            TextButton(
                              onPressed: () => _speedSheet(context, player),
                              child: Text('${player.playbackSpeed}x',
                                  style:
                                      const TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _jumpToTime(
      BuildContext context, PlPlayerController player) async {
    final target = await showDialog<Duration>(
      context: context,
      builder: (_) => _TimeJumpDialog(
        position: player.position.value,
        duration: player.duration.value,
      ),
    );
    if (target != null) {
      await player.seekTo(target, type: 'slider');
    }
  }

  void _speedSheet(BuildContext context, PlPlayerController player) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
            ListTile(
              title: Text('${speed}x'),
              onTap: () {
                player.setPlaybackSpeed(speed);
                Get.back();
              },
            ),
        ],
      ),
    );
  }
}

/// 时间跳转对话框（简化版 AudioTimeJumpDialog：不依赖在线上下文）
class _TimeJumpDialog extends StatefulWidget {
  const _TimeJumpDialog({
    required this.position,
    required this.duration,
  });

  final Duration position;
  final Duration duration;

  @override
  State<_TimeJumpDialog> createState() => _TimeJumpDialogState();
}

class _TimeJumpDialogState extends State<_TimeJumpDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String fmt(Duration d) {
      final s = d.inSeconds;
      return '${(s ~/ 60).toString().padLeft(2, '0')}:'
          '${(s % 60).toString().padLeft(2, '0')}';
    }

    return AlertDialog(
      title: const Text('时间跳转'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前 ${fmt(widget.position)} / 总时长 ${fmt(widget.duration)}'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '目标分钟:秒，如 12:30',
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final text = controller.text.trim();
            final parts = text.split(':');
            int? minutes;
            int? seconds;
            if (parts.length == 2) {
              minutes = int.tryParse(parts[0]);
              seconds = int.tryParse(parts[1]);
            } else if (parts.length == 1) {
              minutes = int.tryParse(parts[0]);
              seconds = 0;
            }
            if (minutes != null && seconds != null) {
              final target = Duration(minutes: minutes, seconds: seconds);
              if (target < widget.duration) {
                Get.back(result: target);
                return;
              }
            }
            Get.back();
          },
          child: const Text('跳转'),
        ),
      ],
    );
  }
}
