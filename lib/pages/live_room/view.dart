import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:floating/floating.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/models/live/message.dart';
import 'package:pilipala/pages/danmaku/index.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/plugin/pl_socket/index.dart';

import 'controller.dart';
import 'widgets/bottom_control.dart';

class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({super.key});

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final LiveRoomController _liveRoomController = Get.put(LiveRoomController());
  late PlPlayerController plPlayerController;
  late Future? _futureBuilder;
  late Future? _futureBuilderFuture;

  bool isShowCover = true;
  bool isPlay = true;
  Floating? floating;
  final ScrollController _scrollController = ScrollController();
  late AnimationController fabAnimationCtr;
  StreamSubscription? _messageSubscription;
  bool _shouldAutoScroll = true;

  final int roomId = int.parse(Get.parameters['roomid']!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      floating = Floating();
    }
    videoSourceInit();
    _futureBuilderFuture = _liveRoomController.queryLiveInfo();
    _scrollController.addListener(_onScroll);
    _messageSubscription = _liveRoomController.messageList.listen((_) {
      if (_shouldAutoScroll) _scrollToBottom();
    });
    fabAnimationCtr = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 0.0,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 回前台：恢复后台期间断掉的直播流并清弹幕
      _liveRoomController.onAppResumed();
    }
  }

  Future<void> videoSourceInit() async {
    _futureBuilder = _liveRoomController.queryLiveInfoH5();
    plPlayerController = _liveRoomController.plPlayerController;
  }

  void _onScroll() {
    // 反向时，展示按钮
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      _shouldAutoScroll = false;
      fabAnimationCtr.forward();
    } else {
      _shouldAutoScroll = true;
      fabAnimationCtr.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController
          .animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      )
          .then((value) {
        _shouldAutoScroll = true;
        // fabAnimationCtr.forward();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _messageSubscription = null;
    if (Get.isRegistered<LiveRoomController>()) {
      Get.delete<LiveRoomController>(force: true);
    }
    plPlayerController.dispose();
    if (floating != null) {
      floating!.dispose();
    }
    _scrollController.dispose();
    fabAnimationCtr.dispose();
    super.dispose();
  }

  Widget _buildLiveEmotePanel() {
    return Obx(() {
      if (_liveRoomController.emoteLoading.value) {
        return const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_liveRoomController.emoteError.value.isNotEmpty) {
        return SizedBox(
          height: 220,
          child: Center(child: Text(_liveRoomController.emoteError.value)),
        );
      }
      final packages = _liveRoomController.emotePackages;
      if (packages.isEmpty) {
        return const SizedBox(
          height: 220,
          child: Center(child: Text('暂无可用表情')),
        );
      }
      return SizedBox(
        height: 250,
        child: DefaultTabController(
          length: packages.length,
          child: Column(
            children: [
              Expanded(
                child: TabBarView(
                  children: packages.map((package) {
                    // 仿 PiliPlus：以包内第一个表情的宽高为基准放大格子
                    final first = package.emoticons.first;
                    final widthFac = first.width <= 0
                        ? 1.0
                        : math.max(1.0, first.width / 80);
                    final heightFac = first.height <= 0
                        ? 1.0
                        : math.max(1.0, first.height / 80);
                    final itemWidth = widthFac * 38;
                    final itemHeight = heightFac * 38;
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: widthFac * 40,
                        mainAxisExtent: heightFac * 40,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: package.emoticons.length,
                      itemBuilder: (context, index) {
                        final emote = package.emoticons[index];
                        return InkWell(
                          onTap: () {
                            if (package.packageType == 3) {
                              _liveRoomController.insertLiveEmote(emote);
                            } else {
                              _liveRoomController.sendLiveEmote(emote);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.network(
                              emote.url ?? '',
                              width: itemWidth,
                              height: itemHeight,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Text(
                                emote.emoji ?? '',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
              TabBar(
                isScrollable: true,
                dividerColor:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                tabs: packages
                    .map((package) => Tab(
                          child: Image.network(
                            package.cover ?? package.emoticons.first.url ?? '',
                            width: 24,
                            height: 24,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.emoji_emotions_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 粉丝牌面板：展示粉丝牌库，点选佩戴，支持取下与刷新
  Widget _buildMedalPanel() {
    final ctr = _liveRoomController;
    return Obx(() {
      if (ctr.medalLoading.value) {
        return const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (ctr.medalError.value.isNotEmpty) {
        return SizedBox(
          height: 220,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ctr.medalError.value),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ctr.refreshMedalList(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        );
      }
      final medals = ctr.medalList;
      if (medals.isEmpty) {
        return const SizedBox(
          height: 220,
          child: Center(child: Text('暂无粉丝牌')),
        );
      }
      return SizedBox(
        height: 250,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
              child: Row(
                children: [
                  Text(
                    '粉丝牌（${medals.length}）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: () => ctr.refreshMedalList(),
                    icon: Icon(
                      Icons.refresh_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: medals.length,
                itemBuilder: (context, index) {
                  final medal = medals[index];
                  final wearing =
                      medal['wear'] == true || medal['status'] == 1;
                  final name = medal['medal_name']?.toString() ?? '';
                  final level = medal['level'];
                  return ListTile(
                    dense: true,
                    onTap: () {
                      if (!wearing) ctr.wearMedalFromPanel(medal);
                    },
                    leading: Icon(
                      Icons.military_tech_outlined,
                      size: 22,
                      color: wearing
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: wearing
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    subtitle: level != null ? Text('Lv.$level') : null,
                    trailing: wearing
                        ? TextButton(
                            onPressed: () => ctr.takeOffMedalFromPanel(),
                            child: const Text('取下'),
                          )
                        : const Icon(
                            Icons.chevron_right,
                            size: 18,
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget videoPlayerPanel = FutureBuilder(
      future: _futureBuilderFuture,
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (_liveRoomController.audioMode) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('直播加载失败: ${snapshot.error}',
                style: const TextStyle(color: Colors.white)),
          );
        }
        if (snapshot.hasData && snapshot.data['status']) {
          plPlayerController = _liveRoomController.plPlayerController;
          final bool isPortrait = _liveRoomController.isPortrait.value;
          // 竖屏时视频居中显示，弹幕叠加在画面上
          return PLVideoPlayer(
            controller: plPlayerController,
            alignment: isPortrait ? Alignment.center : Alignment.center,
            bottomControl: BottomControl(
              controller: plPlayerController,
              liveRoomCtr: _liveRoomController,
              floating: floating,
              onRefresh: () {
                setState(() {
                  _futureBuilderFuture = _liveRoomController.queryLiveInfo();
                });
              },
            ),
            danmuWidget: isPortrait
                ? null
                : PlDanmaku(
                    cid: _liveRoomController.roomId,
                    playerController: plPlayerController,
                    type: 'live',
                    createdController: (e) {
                      _liveRoomController.danmakuController = e;
                      _liveRoomController.flushPendingDanmaku();
                    },
                  ),
          );
        } else {
          return const SizedBox();
        }
      },
    );

    Widget childWhenDisabled = Scaffold(
      primary: true,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 音频模式：以直播封面铺满为画面；其余情况沿用原背景逻辑
          Positioned.fill(
            child: _liveRoomController.audioMode
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // 常驻本地底图：网络封面加载失败时页面不会退化为纯黑
                      const ColoredBox(color: Color(0xFF171717)),
                      Image.asset(
                        'assets/images/live/default_bg.webp',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                      Obx(
                        () {
                          final cover = _liveRoomController
                              .roomInfoH5.value.roomInfo?.cover;
                          final fallbackCover = _liveRoomController.cover;
                          final effective = (cover != null && cover.isNotEmpty)
                              ? cover
                              : fallbackCover;
                          final normalized = effective.startsWith('//')
                              ? 'https:$effective'
                              : effective;
                          if (normalized.isEmpty ||
                              !normalized.startsWith(RegExp(r'https?://'))) {
                            return const SizedBox.shrink();
                          }
                          return Image.network(
                            normalized,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
                  )
                : Obx(
                    () => _liveRoomController
                                    .roomInfoH5.value.roomInfo?.appBackground !=
                                '' &&
                            _liveRoomController
                                    .roomInfoH5.value.roomInfo?.appBackground !=
                                null
                        ? Opacity(
                            opacity: 0.6,
                            child: NetworkImgLayer(
                              width: Get.width,
                              height: Get.height,
                              type: 'bg',
                              src: _liveRoomController.roomInfoH5.value.roomInfo
                                      ?.appBackground ??
                                  '',
                            ),
                          )
                        : Opacity(
                            opacity: 0.6,
                            child: Image.asset(
                              'assets/images/live/default_bg.webp',
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
          ),

          // 音频模式不渲染视频区 Column：该 Column 的 Obx 顶部间距参与 Stack 布局时，
          // 在部分设备上会让整个 Stack 不绘制（直播页全黑），因此音频模式直接跳过。
          if (!_liveRoomController.audioMode)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Obx(
                  () => SizedBox(
                    height: MediaQuery.of(context).padding.top +
                        (_liveRoomController.isPortrait.value ||
                                MediaQuery.of(context).orientation ==
                                    Orientation.landscape
                            ? 0
                            : kToolbarHeight),
                  ),
                ),
                PopScope(
                  canPop: plPlayerController.isFullScreen.value != true,
                  onPopInvoked: (bool didPop) {
                    if (plPlayerController.isFullScreen.value == true) {
                      plPlayerController.triggerFullScreen(status: false);
                    }
                    if (MediaQuery.of(context).orientation ==
                        Orientation.landscape) {
                      verticalScreen();
                    }
                  },
                  child: Obx(
                    () => Container(
                      width: Get.size.width,
                      height: MediaQuery.of(context).orientation ==
                              Orientation.landscape
                          ? Get.size.height
                          : !_liveRoomController.isPortrait.value
                              ? Get.size.width * 9 / 16
                              : Get.size.height -
                                  MediaQuery.of(context).padding.top,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      child: videoPlayerPanel,
                    ),
                  ),
                ),
              ],
            ),
          // 定位 快速滑动到底部
          Positioned(
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 80,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 4),
                end: const Offset(0, 0),
              ).animate(CurvedAnimation(
                parent: fabAnimationCtr,
                curve: Curves.easeInOut,
              )),
              child: ElevatedButton.icon(
                onPressed: () {
                  _scrollToBottom();
                },
                icon: const Icon(Icons.keyboard_arrow_down), // 图标
                label: const Text('新消息'), // 文字
                style: ElevatedButton.styleFrom(
                  // primary: Colors.blue, // 按钮背景颜色
                  // onPrimary: Colors.white, // 按钮文字颜色
                  padding: const EdgeInsets.fromLTRB(14, 12, 20, 12), // 按钮内边距
                ),
              ),
            ),
          ),
          // 顶栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              centerTitle: false,
              titleSpacing: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              toolbarHeight:
                  MediaQuery.of(context).orientation == Orientation.portrait
                      ? 56
                      : 0,
              title: FutureBuilder(
                future: _futureBuilder,
                builder: (context, snapshot) {
                  if (snapshot.data == null) {
                    return const SizedBox();
                  }
                  Map data = snapshot.data as Map;
                  if (data['status']) {
                    return Obx(
                      () => Row(
                        children: [
                          NetworkImgLayer(
                            width: 34,
                            height: 34,
                            type: 'avatar',
                            src: _liveRoomController
                                .roomInfoH5.value.anchorInfo!.baseInfo!.face,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _liveRoomController.roomInfoH5.value.anchorInfo!
                                    .baseInfo!.uname!,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 1),
                              if (_liveRoomController
                                      .roomInfoH5.value.watchedShow !=
                                  null)
                                Text(
                                  _liveRoomController.roomInfoH5.value
                                          .watchedShow!['text_large'] ??
                                      '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  } else {
                    return const SizedBox();
                  }
                },
              ),
            ),
          ),
          // 消息列表：竖屏时叠加在视频底部，从下往上显示，不越过视频中线
          // 音频模式：无视频画面，消息区从顶栏下方开始，占据整个剩余区域
          Obx(
            () {
              final bool isPortrait = _liveRoomController.isPortrait.value;
              final bool isLandscape =
                  MediaQuery.of(context).orientation == Orientation.landscape;
              final double topInset = MediaQuery.of(context).padding.top;
              final double videoHeight = isLandscape
                  ? Get.size.height
                  : isPortrait
                      ? Get.size.height - topInset
                      : Get.size.width * 9 / 16;
              final double videoTop =
                  topInset + (isLandscape || isPortrait ? 0 : kToolbarHeight);
              final double messageTop;
              final double messageBottom;
              if (_liveRoomController.audioMode) {
                messageTop = topInset + kToolbarHeight;
                messageBottom = 90 + MediaQuery.of(context).padding.bottom;
              } else if (isPortrait) {
                messageTop = videoTop + videoHeight / 2;
                messageBottom = Get.size.height -
                    (videoTop +
                        videoHeight -
                        (90 + MediaQuery.of(context).padding.bottom));
              } else {
                messageTop = topInset +
                    kToolbarHeight +
                    (isPortrait ? Get.size.width : Get.size.width * 9 / 16);
                messageBottom = 90 + MediaQuery.of(context).padding.bottom;
              }
              return Positioned(
                top: messageTop,
                bottom: messageBottom,
                left: 0,
                right: 0,
                child: buildMessageListUI(
                  context,
                  _liveRoomController,
                  _scrollController,
                ),
              );
            },
          ),
          // 表情面板：Obx 返回的必须是稳定的 Positioned（仅切换 child），
          // 否则 Positioned/非Positioned 在同一插槽切换会让 Stack 布局异常，
          // 音频模式下表现为整页黑屏。
          Obx(
            () => Positioned(
              left: 0,
              right: 0,
              bottom: 78 + MediaQuery.of(context).padding.bottom,
              child: ((_liveRoomController.showEmotePanel.value ||
                          _liveRoomController.showMedalPanel.value) &&
                      MediaQuery.of(context).orientation ==
                          Orientation.portrait)
                  ? Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: _liveRoomController.showMedalPanel.value
                          ? _buildMedalPanel()
                          : _buildLiveEmotePanel(),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // 消息输入框
          Visibility(
            visible: MediaQuery.of(context).orientation == Orientation.portrait,
            child: Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                    left: 14,
                    right: 14,
                    top: 4,
                    bottom: MediaQuery.of(context).padding.bottom + 20),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Obx(
                        () => IconButton(
                          style: ButtonStyle(
                            padding: MaterialStateProperty.all(EdgeInsets.zero),
                            backgroundColor: MaterialStateProperty.resolveWith(
                                (Set<MaterialState> states) {
                              return Colors.grey.withOpacity(0.1);
                            }),
                          ),
                          onPressed: () {
                            _liveRoomController.danmakuSwitch.value =
                                !_liveRoomController.danmakuSwitch.value;
                          },
                          icon: Icon(
                            _liveRoomController.danmakuSwitch.value
                                ? Icons.subtitles_outlined
                                : Icons.subtitles_off_outlined,
                            size: 19,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Obx(
                      () => IconButton(
                        tooltip: '粉丝牌',
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          _liveRoomController.toggleMedalPanel();
                        },
                        icon: Icon(
                          Icons.military_tech_outlined,
                          size: 20,
                          color: _liveRoomController.showMedalPanel.value
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Obx(
                      () => IconButton(
                        tooltip: '表情',
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          final show =
                              !_liveRoomController.showEmotePanel.value;
                          _liveRoomController.showEmotePanel.value = show;
                          if (show) {
                            _liveRoomController.showMedalPanel.value = false;
                            _liveRoomController.loadLiveEmotes();
                          }
                        },
                        icon: Icon(
                          Icons.emoji_emotions_outlined,
                          size: 20,
                          color: _liveRoomController.showEmotePanel.value
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        onTap: () {
                          _liveRoomController.showEmotePanel.value = false;
                          _liveRoomController.showMedalPanel.value = false;
                        },
                        controller: _liveRoomController.inputController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '发送弹幕',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: IconButton(
                        style: ButtonStyle(
                          padding: MaterialStateProperty.all(EdgeInsets.zero),
                        ),
                        onPressed: () => _liveRoomController.sendMsg(),
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    // 音频模式没有视频纹理，不应交给 PiP 容器切换；部分 Android
    // 设备会把无视频的 PiP 子树渲染成空白，导致背景和弹幕一起不可见。
    if (_liveRoomController.audioMode || !Platform.isAndroid) {
      return childWhenDisabled;
    }
    return PiPSwitcher(
      childWhenDisabled: childWhenDisabled,
      childWhenEnabled: videoPlayerPanel,
      floating: floating,
    );
  }
}

Widget buildMessageListUI(
  BuildContext context,
  LiveRoomController liveRoomController,
  ScrollController scrollController,
) {
  return Obx(
    () => Stack(
      children: [
        MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.5),
                  Colors.black,
                ],
                stops: const [0.01, 0.05, 0.2],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: GestureDetector(
              onTap: () {
                // 键盘失去焦点
                FocusScope.of(context).requestFocus(FocusNode());
              },
              child: ListView.builder(
                controller: scrollController,
                reverse: false,
                itemCount: liveRoomController.messageList.length,
                itemBuilder: (context, index) {
                  final LiveMessageModel liveMsgItem =
                      liveRoomController.messageList[index];
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: liveRoomController.isPortrait.value
                            ? Colors.black.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(20)),
                      ),
                      margin: EdgeInsets.only(
                        top: index == 0 ? 20.0 : 0.0,
                        bottom: 6.0,
                        left: 14.0,
                        right: 14.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 3.0,
                        horizontal: 10.0,
                      ),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(color: Colors.white),
                          children: [
                            if (liveMsgItem.medalName != null &&
                                liveMsgItem.medalLevel != null) ...[
                              TextSpan(
                                text:
                                    '【${liveMsgItem.medalName} lv${liveMsgItem.medalLevel}】',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                ),
                              ),
                            ],
                            TextSpan(
                              text: '${liveMsgItem.userName}: ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  // 处理点击事件
                                  print('Text clicked');
                                },
                            ),
                            TextSpan(
                              children: [
                                ...buildMessageTextSpan(context, liveMsgItem)
                              ],
                              // text: liveMsgItem.message,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (liveRoomController.messageList.isEmpty &&
            liveRoomController.danmakuStatus.value != SocketStatus.connected)
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Text(
              liveRoomController.danmakuError.value.isEmpty
                  ? '正在连接直播弹幕…'
                  : liveRoomController.danmakuError.value,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ),
  );
}

/// 仿 PiliPlus 的直播间表情尺寸规则：
/// - official_ 前缀（官方小黄脸）：原始 width/height 除以设备像素比（缩小到逻辑像素）
/// - 其余装扮表情（room_/upower_ 等）：固定 162 物理像素 / 设备像素比
/// - 普通文本 emots：使用服务端返回的原始 width/height（已为逻辑像素）
(double, double) _liveEmoteDisplaySize(
  Map<String, dynamic> emote,
  double devicePixelRatio,
) {
  final unique =
      (emote['emoticon_unique'] ?? emote['unique'])?.toString().toLowerCase() ??
          '';
  final width = (emote['width'] as num?)?.toDouble() ?? 24;
  final height = (emote['height'] as num?)?.toDouble() ?? width;

  if (unique.startsWith('official_')) {
    return (width / devicePixelRatio, height / devicePixelRatio);
  }
  if (unique.isEmpty ||
      unique.startsWith('room_') ||
      unique.startsWith('upower_')) {
    final side = 162.0 / devicePixelRatio;
    return (side, side);
  }
  // emots 内嵌表情：保持原尺寸
  return (width, height);
}

List<InlineSpan> buildMessageTextSpan(
  BuildContext context,
  LiveMessageModel liveMsgItem,
) {
  final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  final List<InlineSpan> inlineSpanList = [];
  final emote = liveMsgItem.emote;
  if (emote != null && emote['url'] != null) {
    final (width, height) = _liveEmoteDisplaySize(emote, devicePixelRatio);
    inlineSpanList.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: NetworkImgLayer(
          width: width,
          height: height,
          type: 'emote',
          src: emote['url'].toString(),
        ),
      ),
    );
    return inlineSpanList;
  }

  // 是否包含弹幕文本中的表情包
  if (liveMsgItem.emots == null || liveMsgItem.emots!.isEmpty) {
    inlineSpanList.add(TextSpan(text: liveMsgItem.message ?? ''));
  } else {
    final emotsKeys = liveMsgItem.emots!.keys.toList();
    final pattern = RegExp(emotsKeys.map(RegExp.escape).join('|'));
    liveMsgItem.message?.splitMapJoin(
      pattern,
      onMatch: (match) {
        final raw = liveMsgItem.emots![match.group(0)];
        if (raw is! Map) {
          inlineSpanList.add(TextSpan(text: match.group(0) ?? ''));
          return '';
        }
        final emoteMap = Map<String, dynamic>.from(raw);
        if (emoteMap['url'] != null) {
          final (width, height) =
              _liveEmoteDisplaySize(emoteMap, devicePixelRatio);
          inlineSpanList.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: NetworkImgLayer(
                width: width,
                height: height,
                type: 'emote',
                src: emoteMap['url'].toString(),
              ),
            ),
          );
        } else {
          inlineSpanList.add(TextSpan(text: match.group(0) ?? ''));
        }
        return '';
      },
      onNonMatch: (nonMatch) {
        inlineSpanList.add(TextSpan(text: nonMatch));
        return nonMatch;
      },
    );
  }
  return inlineSpanList;
}
