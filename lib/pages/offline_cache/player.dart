import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/models/danmaku/dm.pb.dart';
import 'package:pilipala/models/video_detail_res.dart';
import 'package:pilipala/pages/danmaku/index.dart';
import 'package:pilipala/pages/offline_cache/controller.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/plugin/pl_player/models/bottom_control_type.dart';
import 'package:pilipala/utils/drawer.dart';
import 'package:pilipala/utils/offline_attachments.dart';

/// 本地视频播放页：复用 PLVideoPlayer（与联网视频同一播放器插件栈），
/// 数据源为本地文件（DataSourceType.file），不发起任何网络请求。
/// 同名附属文件（弹幕 .dm / 分段 .vp.json）存在时自动加载。
class OfflinePlayerPage extends StatefulWidget {
  const OfflinePlayerPage({super.key});

  @override
  State<OfflinePlayerPage> createState() => _OfflinePlayerPageState();
}

class _OfflinePlayerPageState extends State<OfflinePlayerPage> {
  late PlPlayerController plPlayerController;
  late List<OfflineVideoItem> playlist;
  int index = 0;

  // 附属数据（弹幕/分段），随当前视频切换而重新加载
  RxList<VideoViewPoint> viewPoints = <VideoViewPoint>[].obs;
  final Rx<List<List<DanmakuElem>>?> localDanmaku = Rx<List<List<DanmakuElem>>?>(null);

  /// 附属文件存在性标记（点击打开时按文件名匹配的结果）：
  /// 命中 .dm → hasLocalDanmaku；命中 .vp.json → hasLocalViewPoints。
  /// 用于 UI 徽标与播放策略，与"解析成功"解耦。
  final RxBool hasLocalDanmaku = false.obs;
  final RxBool hasLocalViewPoints = false.obs;

  OfflineVideoItem get item => playlist[index];

  static const List<BottomControlType> bottomList = [
    BottomControlType.playOrPause,
    BottomControlType.time,
    BottomControlType.space,
    // 分段跳转入口（chapterControl 提供，全屏+有分段数据时显示内容）
    BottomControlType.viewPoints,
    BottomControlType.fit,
    BottomControlType.subtitle,
    BottomControlType.speed,
    BottomControlType.fullscreen,
  ];

  Future<void> _open(int i) async {
    index = i;
    setState(() {});
    viewPoints.clear();
    localDanmaku.value = null;
    hasLocalDanmaku.value = false;
    hasLocalViewPoints.value = false;

    // 附属文件匹配：按视频文件名（sanitize 后）去 danmaku/ 目录找
    // <同名>.dm（弹幕）与 <同名>.vp.json（分段/进度条章节）。
    // 命中 → 记住该视频含弹幕/分段并加载后播放；未命中 → 纯视频播放。
    // 任何异常都不阻塞播放（与在线播放的降级策略一致）。
    final String safeTitle = OfflineAttachments.sanitizeTitle(item.title);
    try {
      final bool dmExists =
          await OfflineAttachments.hasDanmakuFile(safeTitle);
      hasLocalDanmaku.value = dmExists;
      if (dmExists) {
        final List<List<DanmakuElem>>? dm =
            await OfflineAttachments.loadDanmaku(safeTitle);
        // 文件存在但解析失败（损坏/格式不符）：按无弹幕处理
        hasLocalDanmaku.value = dm != null;
        localDanmaku.value = dm;
      }
    } catch (_) {
      localDanmaku.value = null;
      hasLocalDanmaku.value = false;
    }
    try {
      final bool vpExists =
          await OfflineAttachments.hasViewPointsFile(safeTitle);
      hasLocalViewPoints.value = vpExists;
      if (vpExists) {
        final List<Map<String, dynamic>>? vp =
            await OfflineAttachments.loadViewPoints(safeTitle);
        if (vp != null) {
          viewPoints.assignAll(vp
              .map(VideoViewPoint.fromJson)
              .where((p) => p.from != null && p.content?.isNotEmpty == true)
              .toList()
                ..sort((a, b) => a.from!.compareTo(b.from!)));
        }
      }
    } catch (_) {}

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

    // 本页固定竖屏；全屏由播放器切换横屏，退出时恢复
    verticalScreen();

    plPlayerController = PlPlayerController(videoType: 'archive');
    // 倍速选择弹窗（BottomControlType.speed 触发）
    plPlayerController.onSpeedTap = _showSpeedSheet;
    _open(0);
  }

  @override
  void dispose() {
    // 全屏/横屏状态下退出页面时恢复竖屏与系统 UI，避免整个应用卡在横屏
    if (plPlayerController.isFullScreen.value) {
      plPlayerController.toggleFullScreen(false);
      exitFullScreen();
    }
    verticalScreen();
    plPlayerController.dispose();
    super.dispose();
  }

  /// 倍速选择弹窗（对齐视频详情页 showSetSpeedSheet）
  void _showSpeedSheet() {
    final double currentSpeed = plPlayerController.playbackSpeed;
    final List<double> speedsList = plPlayerController.speedsList;
    showDialog(
      context: Get.context!,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('播放速度'),
          content: Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              for (final double i in speedsList) ...<Widget>[
                if (i == currentSpeed)
                  FilledButton(
                    onPressed: () async {
                      await plPlayerController.setPlaybackSpeed(i);
                      Get.back();
                    },
                    child: Text(i.toString()),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () async {
                      await plPlayerController.setPlaybackSpeed(i);
                      Get.back();
                    },
                    child: Text(i.toString()),
                  ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Get.back(),
              child: Text(
                '取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () async {
                await plPlayerController.setDefaultSpeed();
                Get.back();
              },
              child: const Text('恢复默认'),
            ),
          ],
        );
      },
    );
  }

  /// 分段跳转控件（移植自在线视频详情页）：全屏 + 有分段数据时显示，
  /// 点击打开右侧分段列表，选择章节直接 seek
  Widget _buildChapterControl(BuildContext context) {
    return Obx(() {
      if (!plPlayerController.isFullScreen.value || viewPoints.isEmpty) {
        return const SizedBox.shrink();
      }
      final int currentIndex = viewPoints.lastIndexWhere(
        (point) =>
            point.from != null &&
            point.from! <= plPlayerController.position.value.inSeconds,
      );
      final VideoViewPoint? current =
          currentIndex >= 0 ? viewPoints[currentIndex] : null;
      return TextButton(
        onPressed: () => _showChapterPicker(context),
        style: ButtonStyle(
          padding: MaterialStateProperty.all(EdgeInsets.zero),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.segment, color: Colors.white, size: 15),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                current?.content ?? '分段',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showChapterPicker(BuildContext context) {
    DrawerUtils.showRightDialog(
      width: 380,
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('分段信息', style: TextStyle(fontSize: 16)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => SmartDialog.dismiss(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Obx(
                () => ListView.builder(
                  itemCount: viewPoints.length,
                  itemBuilder: (context, index) {
                    final VideoViewPoint point = viewPoints[index];
                    final int positionSeconds =
                        plPlayerController.position.value.inSeconds;
                    final bool current = point.from != null &&
                        positionSeconds >= point.from! &&
                        (point.to == null || positionSeconds < point.to!);
                    return InkWell(
                      onTap: point.from == null
                          ? null
                          : () {
                              SmartDialog.dismiss();
                              plPlayerController.seekTo(
                                Duration(seconds: point.from!),
                                type: 'slider',
                              );
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (point.imgUrl?.isNotEmpty == true)
                              NetworkImgLayer(
                                width: 140,
                                height: 88,
                                type: 'emote',
                                src: point.imgUrl!,
                              ),
                            if (point.imgUrl?.isNotEmpty == true)
                              const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    point.content ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: current
                                        ? TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_formatChapterTime(point.from ?? 0)} - '
                                    '${_formatChapterTime(point.to ?? 0)}',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

  String _formatChapterTime(int seconds) {
    final duration = Duration(seconds: seconds);
    final int hours = duration.inHours;
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }

  PreferredSizeWidget _buildHeaderControl() {
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        children: [
          ComBtn(
            icon: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
            fuc: () => Get.back(),
          ),
          const Spacer(),
          // 弹幕开关（有本地弹幕时才有意义）
          ComBtn(
            icon: Obx(
              () => Icon(
                localDanmaku.value != null
                    ? (plPlayerController.isOpenDanmu.value
                        ? Icons.subtitles
                        : Icons.subtitles_outlined)
                    : Icons.subtitles_outlined,
                size: 20,
                color: localDanmaku.value != null
                    ? Colors.white
                    : Colors.white.withOpacity(0.4),
              ),
            ),
            fuc: () {
              if (localDanmaku.value == null) {
                SmartDialog.showToast('该视频没有本地弹幕');
                return;
              }
              plPlayerController.isOpenDanmu.value =
                  !(plPlayerController.isOpenDanmu.value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerArea() {
    return Obx(() {
      // 首次必须等 VideoController 创建完成后再挂载 PLVideoPlayer：
      // 其 initState 会同步读取 videoController!，过早挂载会导致子树构建失败
      // （表现为黑屏但有声音）
      final DataStatus status =
          plPlayerController.dataStatus.status.value;
      if (status == DataStatus.error) {
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('播放失败', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              IconButton.filled(
                onPressed: () => _open(index),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        );
      }
      final bool ready = plPlayerController.videoController != null;
      if (!ready) {
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(color: Colors.white),
        );
      }
      return PLVideoPlayer(
        controller: plPlayerController,
        headerControl: _buildHeaderControl(),
        bottomList: bottomList,
        chapterControl: _buildChapterControl(context),
        danmuWidget: PlDanmaku(
          key: Key(item.path),
          cid: 0,
          playerController: plPlayerController,
          type: 'offline',
          localSegments: localDanmaku.value,
        ),
        viewPoints: viewPoints.toList(),
        showViewPointBar: true,
        onSeekViewPoint: (position) =>
            plPlayerController.seekTo(position, type: 'slider'),
      );
    });
  }

  Widget _buildListPanel(BuildContext context) {
    final List<OfflineVideoItem> others =
        playlist.where((e) => e.path != item.path).toList();
    return Container(
      width: double.infinity,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Obx(
              () => Text(
                '${item.sizeLabel} · 本地视频'
                '${hasLocalViewPoints.value ? ' · 含分段' : ''}'
                '${hasLocalDanmaku.value ? ' · 含弹幕' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '其它下载 · ${others.length}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: others.isEmpty
                ? const Center(child: Text('暂无其它下载视频'))
                : ListView.builder(
                    itemCount: others.length,
                    itemBuilder: (context, i) {
                      final OfflineVideoItem e = others[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.movie_outlined),
                        title: Text(
                          e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          e.sizeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        onTap: () => _open(playlist.indexOf(e)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PopScope(
        // 全屏时拦截返回键：先退出全屏，再次返回才离开页面（对齐视频详情页）
        canPop: !plPlayerController.isFullScreen.value,
        onPopInvoked: (bool didPop) {
          if (plPlayerController.isFullScreen.value) {
            plPlayerController.triggerFullScreen(status: false);
          }
        },
        child: plPlayerController.isFullScreen.value
            ? Scaffold(
                backgroundColor: Colors.black,
                body: SizedBox.expand(child: _buildPlayerArea()),
              )
            : Scaffold(
                backgroundColor: Colors.black,
                body: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width,
                        height: MediaQuery.sizeOf(context).width * 9 / 16,
                        child: _buildPlayerArea(),
                      ),
                      Expanded(child: _buildListPanel(context)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
