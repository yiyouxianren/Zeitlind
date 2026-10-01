import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:ns_danmaku/ns_danmaku.dart';
import 'package:pilipala/models/danmaku/dm.pb.dart';
import 'package:pilipala/pages/danmaku/index.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/utils/danmaku.dart';
import 'package:pilipala/utils/storage.dart';

/// 传入播放器控制器，监听播放进度，加载对应弹幕
class PlDanmaku extends StatefulWidget {
  final int cid;
  final PlPlayerController playerController;
  final String type;
  final Function(DanmakuController)? createdController;

  /// 离线模式（type == 'offline'）传入本地弹幕分段
  final List<List<DanmakuElem>>? localSegments;

  const PlDanmaku({
    super.key,
    required this.cid,
    required this.playerController,
    this.type = 'video',
    this.createdController,
    this.localSegments,
  });

  @override
  State<PlDanmaku> createState() => _PlDanmakuState();
}

class _PlDanmakuState extends State<PlDanmaku> {
  late PlPlayerController playerController;
  late PlDanmakuController _plDanmakuController;
  DanmakuController? _controller;
  // bool danmuPlayStatus = true;
  Box setting = GStrorage.setting;
  late bool enableShowDanmaku;
  late List blockTypes;
  late double showArea;
  late double opacityVal;
  late double fontSizeVal;
  late double danmakuDurationVal;
  late double strokeWidth;
  int latestAddedPosition = -1;

  @override
  void initState() {
    super.initState();
    enableShowDanmaku =
        setting.get(SettingBoxKey.enableShowDanmaku, defaultValue: false);
    _plDanmakuController = PlDanmakuController(widget.cid, widget.type,
        localSegments: widget.localSegments);
    playerController = widget.playerController;
    final bool isVideoLike =
        widget.type == 'video' || widget.type == 'offline';
    if (mounted && isVideoLike) {
      if (enableShowDanmaku || playerController.isOpenDanmu.value) {
        _plDanmakuController.initiate(
            playerController.duration.value.inMilliseconds,
            playerController.position.value.inMilliseconds);
      }
      playerController
        ..addStatusLister(playerListener)
        ..addPositionListener(videoPositionListen);
    }
    if (isVideoLike) {
      playerController.isOpenDanmu.listen((p0) {
        if (p0 && !_plDanmakuController.initiated) {
          _plDanmakuController.initiate(
              playerController.duration.value.inMilliseconds,
              playerController.position.value.inMilliseconds);
        }
      });
    }
    blockTypes = playerController.blockTypes;
    showArea = playerController.showArea;
    opacityVal = playerController.opacityVal;
    fontSizeVal = playerController.fontSizeVal;
    strokeWidth = playerController.strokeWidth;
    danmakuDurationVal = playerController.danmakuDurationVal;
  }

  // 播放器状态监听
  void playerListener(PlayerStatus? status) {
    if (status == PlayerStatus.paused) {
      _controller!.pause();
    }
    if (status == PlayerStatus.playing) {
      _controller!.onResume();
    }
  }

  void videoPositionListen(Duration position) {
    if (!playerController.isOpenDanmu.value) {
      return;
    }
    int currentPosition = position.inMilliseconds;
    currentPosition -= currentPosition % 100; //取整百的毫秒数

    if (currentPosition == latestAddedPosition) {
      return;
    }
    latestAddedPosition = currentPosition;

    if (_controller == null) {
      return;
    }

    List<DanmakuElem>? currentDanmakuList;
    // 直播弹幕未按进度分段加载，直接取分段会越界
    if (_plDanmakuController.initiated) {
      currentDanmakuList =
          _plDanmakuController.getCurrentDanmaku(currentPosition);
    }

    if (currentDanmakuList != null) {
      Color? defaultColor = playerController.blockTypes.contains(6)
          ? DmUtils.decimalToColor(16777215)
          : null;

      _controller!.addItems(currentDanmakuList
          .map((e) => DanmakuItem(
                e.content,
                color: defaultColor ?? DmUtils.decimalToColor(e.color),
                time: e.progress,
                type: DmUtils.getPosition(e.mode),
              ))
          .toList());
    }
  }

  @override
  void dispose() {
    playerController.removePositionListener(videoPositionListen);
    playerController.removeStatusLister(playerListener);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 离线模式切换视频：localSegments 引用变化时重建弹幕数据源，
    // 否则 State 复用旧视频的分段表，切换后弹幕消失（须重进页面才恢复）
    if (widget.localSegments != oldWidget.localSegments ||
        widget.cid != oldWidget.cid) {
      latestAddedPosition = -1;
      _plDanmakuController = PlDanmakuController(widget.cid, widget.type,
          localSegments: widget.localSegments);
      if (playerController.isOpenDanmu.value) {
        _plDanmakuController.initiate(
            playerController.duration.value.inMilliseconds,
            playerController.position.value.inMilliseconds);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      //竖屏时（高宽比>=3/4），将弹幕容器限制在画面高度的2/3区域内，
      //弹幕从画面左下角一条条往上顶，最多到画面三分之二的位置
      double danmuArea = 1.0;
      if (box.maxHeight > box.maxWidth * 0.75 && box.maxHeight > 100) {
        danmuArea = (box.maxHeight * 2 / 3) / box.maxHeight;
      }
      // double initDuration = box.maxWidth / 12;
      return Obx(
        () => AnimatedOpacity(
          opacity: playerController.isOpenDanmu.value ? 1 : 0,
          duration: const Duration(milliseconds: 100),
          child: DanmakuView(
            createdController: (DanmakuController e) async {
              playerController.danmakuController = _controller = e;
              widget.createdController?.call(e);
            },
            option: DanmakuOption(
              fontSize: 15 * fontSizeVal,
              area: danmuArea,
              opacity: opacityVal,
              hideTop: blockTypes.contains(5),
              hideScroll: blockTypes.contains(2),
              hideBottom: blockTypes.contains(4),
              duration: danmakuDurationVal / playerController.playbackSpeed,
              strokeWidth: strokeWidth,
              // initDuration /
              //     (danmakuSpeedVal * widget.playerController.playbackSpeed),
            ),
            statusChanged: (isPlaying) {},
          ),
        ),
      );
    });
  }
}
