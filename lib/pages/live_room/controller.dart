import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:ns_danmaku/ns_danmaku.dart';
import 'package:pilipala/http/constants.dart';
import 'package:pilipala/http/api.dart';
import 'package:pilipala/http/init.dart';
import 'package:pilipala/http/live.dart';
import 'package:pilipala/models/live/emote.dart';
import 'package:pilipala/models/live/message.dart';
import 'package:pilipala/models/live/quality.dart';
import 'package:pilipala/models/live/room_info.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/plugin/pl_socket/index.dart';
import 'package:pilipala/utils/live.dart';
import '../../models/live/room_info_h5.dart';
import '../../utils/storage.dart';
import '../../utils/video_utils.dart';

class LiveRoomController extends GetxController {
  String cover = '';
  late int roomId;
  int routeRoomId = 0;
  dynamic liveItem;
  late String heroTag;
  double volume = 0.0;
  // 静音状态
  RxBool volumeOff = false.obs;
  PlPlayerController plPlayerController = PlPlayerController(videoType: 'live');
  Rx<RoomInfoH5Model> roomInfoH5 = RoomInfoH5Model().obs;
  late bool enableCDN;
  late int currentQn;
  int? tempCurrentQn;
  late List<Map<String, dynamic>> acceptQnList;
  RxString currentQnDesc = ''.obs;
  Box userInfoCache = GStrorage.userInfo;
  int userId = 0;
  PlSocket? plSocket;
  Rx<SocketStatus> danmakuStatus = SocketStatus.closed.obs;
  RxString danmakuError = ''.obs;
  bool _danmakuInitializing = false;
  // 弹幕消息列表
  RxList<LiveMessageModel> messageList = <LiveMessageModel>[].obs;
  DanmakuController? danmakuController;
  final List<DanmakuItem> _pendingDanmakuItems = <DanmakuItem>[];
  RxString sendStatus = ''.obs;
  TextEditingController inputController = TextEditingController();
  // 加入直播间提示
  RxMap<String, String> joinRoomTip = {'userName': '', 'message': ''}.obs;
  // 直播间弹幕开关 默认打开
  RxBool danmakuSwitch = true.obs;
  late String buvid;
  RxBool isPortrait = false.obs;
  RxBool showEmotePanel = false.obs;
  RxBool emoteLoading = false.obs;
  RxString emoteError = ''.obs;
  RxList<LiveEmotePackage> emotePackages = <LiveEmotePackage>[].obs;
  bool _emotesLoaded = false;
  late final bool audioMode;
  int _liveQueryGeneration = 0;

  @override
  void onInit() {
    super.onInit();
    currentQn = setting.get(SettingBoxKey.defaultLiveQa,
        defaultValue: LiveQuality.values.last.code);
    roomId = int.parse(Get.parameters['roomid']!);
    routeRoomId = roomId;
    audioMode =
        setting.get(SettingBoxKey.enableAudioMode, defaultValue: false) as bool;
    if (Get.arguments != null) {
      liveItem = Get.arguments['liveItem'];
      heroTag = Get.arguments['heroTag'] ?? '';
      if (liveItem != null) {
        cover = (liveItem.pic != null && liveItem.pic != '')
            ? liveItem.pic
            : (liveItem.cover != null && liveItem.cover != '')
                ? liveItem.cover
                : '';
      }
      Request.getBuvid().then((value) => buvid = value);
    }
    // CDN优化
    enableCDN = setting.get(SettingBoxKey.enableCDN, defaultValue: true);
    final userInfo = userInfoCache.get('userInfoCache');
    if (userInfo != null && userInfo.mid != null) {
      userId = userInfo.mid;
    }
    _initDanmaku();
    danmakuSwitch.listen((p0) {
      plPlayerController.isOpenDanmu.value = p0;
    });
  }

  Future<void> _initDanmaku() async {
    if (_danmakuInitializing) return;
    _danmakuInitializing = true;
    danmakuError.value = '';
    danmakuStatus.value = SocketStatus.connecting;
    try {
      // 与 PiliPlus 一致：以真实 roomId（短号会被 getRoomPlayInfo 转成真实房间号）获取弹幕 token
      final room =
          await LiveHttp.liveRoomInfo(roomId: routeRoomId, qn: currentQn);
      if (room['status'] == true && room['data'].roomId is int) {
        roomId = room['data'].roomId as int;
      }
      await startLiveMsg();
    } catch (error) {
      danmakuStatus.value = SocketStatus.failed;
      danmakuError.value = '弹幕初始化失败: $error';
    } finally {
      _danmakuInitializing = false;
    }
  }

  // 弹幕信息流（对齐 PiliPlus startLiveMsg/initDm）
  Future<void> startLiveMsg() async {
    final res = await LiveHttp.liveDanmakuInfo(roomId: roomId);
    debugPrint('liveDanmakuInfo status=${res['status']} msg=${res['msg']}');
    if (res['status'] == true) {
      final token = res['data']['token']?.toString() ?? '';
      if (token.isEmpty || token.length < 10) {
        danmakuStatus.value = SocketStatus.failed;
        danmakuError.value = '弹幕 Token 为空，请检查登录状态';
        return;
      }
      initDm(res['data']);
    } else {
      danmakuStatus.value = SocketStatus.failed;
      danmakuError.value = res['msg']?.toString() ?? '获取弹幕连接信息失败';
    }
  }

  Future<void> initDm(dynamic data) async {
    final token = data['token']?.toString() ?? '';
    final hostList = data['host_list'];
    debugPrint(
        'initDm tokenLen=${token.length} hostCount=${hostList is List ? hostList.length : 0}');
    if (token.isEmpty || hostList is! List || hostList.isEmpty) {
      danmakuStatus.value = SocketStatus.failed;
      danmakuError.value = '直播弹幕配置无效';
      return;
    }
    // 优先 wss；部分网络环境下 wss 连接会被弹幕服务器静默拒绝，保留明文 ws 兜底
    final wssServers = <String>[];
    final wsServers = <String>[];
    for (final e in hostList.whereType<Map>()) {
      final host = e['host']?.toString();
      final wssPort = e['wss_port'];
      final wsPort = e['ws_port'];
      if (host == null || host.isEmpty) continue;
      if (wssPort != null) wssServers.add('wss://$host:$wssPort/sub');
      if (wsPort != null) wsServers.add('ws://$host:$wsPort/sub');
    }
    if (wssServers.isEmpty && wsServers.isEmpty) {
      danmakuStatus.value = SocketStatus.failed;
      danmakuError.value = '直播弹幕节点无效';
      return;
    }
    final servers = [...wssServers, ...wsServers];
    // 调试：可通过 setting 的 liveDebugProxyUrl 覆盖弹幕服务器（排查网络问题用）
    final debugProxy =
        setting.get('liveDebugProxyUrl', defaultValue: '') as String;
    final effectiveServers = debugProxy.isNotEmpty ? [debugProxy] : servers;
    _fallbackStage = 0;
    closeLiveMsg();
    plSocket =
        await _buildSocket(servers: effectiveServers, wsServers: wsServers);
    plSocket?.uid = userId;
    plSocket?.roomid = roomId;
    plSocket?.key = token;
    plSocket?.connect();
  }

  // 认证被拒时逐级降级：游客 uid=0 重连 → 明文 ws 重连
  // 预取 cookie 头（显式携带登录 cookie，避免游客 token）
  Future<String> _getCookieHeader() async {
    try {
      final cookies = await Request.cookieManager.cookieJar
          .loadForRequest(Uri.parse(Api.getDanmuInfo));
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (e) {
      debugPrint('get cookie header failed: $e');
      return '';
    }
  }

  Future<PlSocket> _buildSocket(
      {required List<String> servers, List<String>? wsServers}) async {
    final cookieHeader = await _getCookieHeader();
    return PlSocket(
      url: servers.first,
      urls: servers,
      heartTime: 30,
      extraHeaders: {'cookie': cookieHeader},
      onStatusCb: (status) {
        danmakuStatus.value = status;
      },
      onMessageCb: _danmakuListener,
      onAuthRejectedCb: () {
        if (_fallbackStage >= 2) return;
        _fallbackStage++;
        final stage = _fallbackStage;
        debugPrint('auth rejected, fallback stage=$stage');
        Future<void>.delayed(const Duration(milliseconds: 500), () async {
          if (plSocket == null) return;
          final savedToken = plSocket?.key;
          final nextUid = stage == 1 ? 0 : plSocket!.uid;
          final nextUrls = stage == 1
              ? servers
              : ((wsServers?.isNotEmpty ?? false) ? wsServers! : servers);
          final fallbackSocket =
              await _buildSocket(servers: nextUrls, wsServers: wsServers);
          fallbackSocket.roomid = roomId;
          fallbackSocket.key = savedToken;
          closeLiveMsg();
          plSocket = fallbackSocket;
          plSocket?.uid = nextUid;
          plSocket?.connect();
        });
      },
      onErrorCb: (e) {
        danmakuStatus.value = SocketStatus.failed;
        danmakuError.value = '弹幕连接失败，请稍后重试';
      },
    );
  }

  int _fallbackStage = 0;

  void closeLiveMsg() {
    plSocket?.onClose(notify: false);
    plSocket = null;
  }

  @pragma('vm:notify-debugger-on-exception')
  void _danmakuListener(dynamic message) {
    try {
      if (message is! String) return;
      final liveMsg = LiveUtils.parseMessage(message);
      if (liveMsg == null) return;
      _handleLiveMessage(liveMsg);
    } catch (error) {
      debugPrint('danmaku listener error: $error');
    }
  }

  void _handleLiveMessage(LiveMessageModel liveMsg) {
    switch (liveMsg.type) {
      case LiveMessageType.join:
      case LiveMessageType.follow:
        joinRoomTip.value = {
          'userName': liveMsg.userName,
          'message': liveMsg.message ?? '',
        };
        return;
      case LiveMessageType.online:
        return;
      case LiveMessageType.chat:
      case LiveMessageType.superChat:
        break;
    }

    messageList.add(liveMsg);
    const maxMessages = 500;
    if (messageList.length > maxMessages) {
      messageList.removeRange(0, messageList.length - maxMessages);
    }

    if (liveMsg.type == LiveMessageType.chat &&
        liveMsg.uid != null &&
        liveMsg.uid == userId &&
        sendStatus.value.contains('等待')) {
      sendStatus.value = '弹幕已收到';
      SmartDialog.showToast('弹幕已发送并收到直播回流');
    }

    if (liveMsg.type == LiveMessageType.chat && danmakuSwitch.value) {
      final item = DanmakuItem(
        liveMsg.message ?? '',
        color: Color.fromARGB(
            255, liveMsg.color.r, liveMsg.color.g, liveMsg.color.b),
      );
      if (danmakuController != null) {
        flushPendingDanmaku();
        danmakuController!.addItems([item]);
      } else {
        _pendingDanmakuItems.add(item);
      }
    }
  }

  Future<void> playerInit(String source, {bool audioOnly = false}) async {
    await plPlayerController.setDataSource(
      DataSource(
        videoSource: audioOnly ? null : source,
        audioSource: audioOnly ? source : null,
        type: DataSourceType.network,
        audioOnly: audioOnly,
        httpHeaders: {
          'user-agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_3_1) AppleWebKit/605.1.15 Version/16.4 Safari/605.1.15',
          'referer': HttpString.baseUrl,
        },
      ),
      // 硬解
      enableHA: true,
      autoplay: true,
    );
    plPlayerController.isOpenDanmu.value = danmakuSwitch.value;
    _listenPlayerErrors();
    _startStallWatchdog();
    heartBeat();
  }

  // ============ 直播流断流自动恢复 ============
  // B站直播流断开（网络抖动/服务器断流/后台恢复surface丢失）时 mpv 会卡死，
  // 退出重进才能恢复；这里参照 PiliPlus 的做法：监听 mpv 错误 + 卡死检测，自动重拉流。
  StreamSubscription? _playerErrorSub;
  bool _recovering = false;

  void _listenPlayerErrors() {
    _playerErrorSub?.cancel();
    final player = plPlayerController.videoPlayerController;
    if (player == null) return;
    _playerErrorSub = player.stream.error.listen((String event) {
      debugPrint('live player error: $event');
      final fatal = event.startsWith('tcp: ffurl_read returned ') ||
          event.startsWith('Failed to open https://') ||
          event.startsWith('Can not open external file https://');
      if (fatal) {
        Future<void>.delayed(const Duration(seconds: 3), () {
          // 仅在仍在直播页且确实卡住时恢复
          if (!_recovering && plPlayerController.isBuffering.value) {
            recoverLiveStream(reason: 'stream error');
          }
        });
      }
    });
  }

  Timer? _stallWatchdog;
  Duration _lastWatchdogPosition = Duration.zero;
  DateTime _lastWatchdogTime = DateTime.now();

  // 画面卡死但 mpv 未报错时兜底：15秒内播放位置无推进则重拉流
  void _startStallWatchdog() {
    _stallWatchdog?.cancel();
    _lastWatchdogPosition = plPlayerController.position.value;
    _lastWatchdogTime = DateTime.now();
    _stallWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_recovering) return;
      final pos = plPlayerController.position.value;
      final now = DateTime.now();
      if (pos > _lastWatchdogPosition) {
        _lastWatchdogPosition = pos;
        _lastWatchdogTime = now;
        return;
      }
      if (now.difference(_lastWatchdogTime).inSeconds >= 15 &&
          !plPlayerController.isBuffering.value) {
        debugPrint('stall watchdog triggered: pos=$pos');
        recoverLiveStream(reason: 'stall watchdog');
      }
    });
  }

  // 重拉直播流：重新请求房间信息拿到新的带鉴权地址后重开播放器
  Future<void> recoverLiveStream({String reason = ''}) async {
    if (_recovering) return;
    _recovering = true;
    debugPrint('recoverLiveStream reason=$reason');
    try {
      SmartDialog.showToast('直播流断开，正在恢复…',
          displayTime: const Duration(milliseconds: 1200));
      await queryLiveInfo();
    } catch (e) {
      debugPrint('recoverLiveStream failed: $e');
    } finally {
      // 给新流一点稳定时间再放开 watchdog
      _lastWatchdogPosition = Duration.zero;
      _lastWatchdogTime = DateTime.now();
      Future<void>.delayed(const Duration(seconds: 10), () {
        _recovering = false;
      });
    }
  }

  // 从后台回到前台时调用：恢复卡死的流并清弹幕
  void onAppResumed() {
    debugPrint('live room onAppResumed');
    danmakuController?.clear();
    // 后台久了流通常已断，直接重拉
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      recoverLiveStream(reason: 'app resumed');
    });
  }

  Future queryLiveInfo() async {
    final int queryGeneration = ++_liveQueryGeneration;
    try {
      final res = await LiveHttp.liveRoomInfo(
        roomId: roomId,
        qn: currentQn,
        onlyAudio: audioMode,
      );
      if (queryGeneration != _liveQueryGeneration) return res;
      if (res['status'] != true) {
        return res;
      }
      final data = res['data'] as RoomInfoModel?;
      if (data != null) {
        isPortrait.value = data.isPortrait ?? false;
      }
      final playurlInfo = data?.playurlInfo;
      final streams = playurlInfo?.playurl?.stream ?? const <Streams>[];
      final formats = streams
          .expand((stream) => stream.format ?? const <FormatItem>[])
          .where((format) => format.codec?.isNotEmpty == true)
          .toList();
      if (data == null || formats.isEmpty) {
        return {
          'status': false,
          'data': [],
          'msg': '直播播放地址为空，可能是直播间暂未开播或接口返回异常',
        };
      }

      // 不假设第一条 format/codec 一定存在；某些房间会返回多协议或不完整画质列表。
      final codec = formats
          .expand((format) => format.codec ?? const <CodecItem>[])
          .where((item) =>
              item.baseUrl != null && item.urlInfo?.isNotEmpty == true)
          .toList();
      if (codec.isEmpty) {
        return {
          'status': false,
          'data': [],
          'msg': '直播间没有可用的视频流地址',
        };
      }
      final item = codec.first;
      final resolvedQn = item.currentQn;
      if (resolvedQn != null && LiveQualityCode.fromCode(resolvedQn) != null) {
        currentQn = resolvedQn;
      }
      tempCurrentQn = null;

      final availableQn = <int>{
        for (final entry
            in formats.expand((format) => format.codec ?? const <CodecItem>[]))
          if (entry.currentQn != null) entry.currentQn!,
      };
      acceptQnList = availableQn.map((code) {
        final quality = LiveQualityCode.fromCode(code);
        return {
          'code': code,
          'desc': quality?.description ?? '画质 $code',
        };
      }).toList();
      final currentQuality = LiveQualityCode.fromCode(currentQn);
      currentQnDesc.value = currentQuality?.description ?? '当前画质';

      final urlInfo = item.urlInfo?.first;
      final baseUrl = item.baseUrl;
      if (urlInfo == null ||
          baseUrl == null ||
          urlInfo.host == null ||
          urlInfo.extra == null) {
        return {
          'status': false,
          'data': [],
          'msg': '直播间播放地址格式异常',
        };
      }
      final videoUrl = enableCDN
          ? VideoUtils.getCdnUrl(item)
          : urlInfo.host! + baseUrl + urlInfo.extra!;
      if (queryGeneration != _liveQueryGeneration) return res;
      await playerInit(videoUrl, audioOnly: audioMode);
      return res;
    } catch (error, stackTrace) {
      debugPrint('queryLiveInfo failed room=$roomId error=$error\n$stackTrace');
      return {
        'status': false,
        'data': [],
        'msg': '直播加载失败: $error',
      };
    }
  }

  void setVolumn(value) {
    if (value == 0) {
      // 设置音量
      volumeOff.value = false;
    } else {
      // 取消音量
      volume = value;
      volumeOff.value = true;
    }
  }

  Future queryLiveInfoH5() async {
    var res = await LiveHttp.liveRoomInfoH5(roomId: roomId);
    if (res['status']) {
      roomInfoH5.value = res['data'];
      unawaited(_autoWearFansMedal());
    }
    return res;
  }

  // ============ 进直播间自动佩戴主播粉丝牌 ============
  // 查询我的粉丝牌库，命中本直播间主播的粉丝牌则换上；
  // 没有则不佩戴。离开直播间时恢复进房前的佩戴状态。
  int? _autoWornMedalId;
  int? _prevWornMedalId;
  String? _prevWornMedalName;

  Future<void> _autoWearFansMedal() async {
    if (userId == 0) return; // 未登录
    // 设置开关：直播设置 → 自动佩戴粉丝牌
    final enabled = setting.get(SettingBoxKey.autoWearFansMedal,
        defaultValue: true) as bool;
    if (!enabled) return;
    try {
      final anchorUid = roomInfoH5.value.roomInfo?.uid;
      if (anchorUid == null) return;
      final medals = await LiveHttp.fansMedalList();
      if (medals.isEmpty) return;
      Map<String, dynamic>? target;
      Map<String, dynamic>? currentWorn;
      for (final m in medals) {
        final wearing = m['wear'] == true || m['status'] == 1;
        if (wearing) currentWorn = m;
        if (m['target_id'] == anchorUid) target = m;
      }
      _prevWornMedalId = currentWorn?['medal_id'] as int?;
      _prevWornMedalName = currentWorn?['medal_name'] as String?;
      // 已戴着本直播间粉丝牌则无需操作
      if (target != null && identical(target, currentWorn)) {
        _medalToast('已佩戴粉丝牌「${target['medal_name']}」，无需换牌');
        return;
      }
      if (target != null) {
        final ok = await LiveHttp.wearFansMedal(
          medalId: target['medal_id'] as int,
          status: 1,
        );
        if (ok) {
          _autoWornMedalId = target['medal_id'] as int;
          debugPrint('已自动佩戴粉丝牌：${target['medal_name']}');
          _medalToast('已自动佩戴粉丝牌「${target['medal_name']}」');
        } else {
          _medalToast('佩戴粉丝牌「${target['medal_name']}」失败');
        }
      } else {
        // 粉丝牌库里没有本直播间主播的牌：不展示粉丝牌
        debugPrint('粉丝牌库中无本直播间主播的粉丝牌，不佩戴');
        _medalToast('未持有该主播的粉丝牌，不佩戴');
      }
    } catch (e) {
      debugPrint('auto wear fans medal error: $e');
      _medalToast('粉丝牌信息获取失败');
    }
  }

  void _medalToast(String msg) {
    if (!Get.isRegistered<LiveRoomController>()) return;
    SmartDialog.showToast(msg);
  }

  // ============ 手动更换粉丝牌面板 ============
  RxBool showMedalPanel = false.obs;
  RxBool medalLoading = false.obs;
  RxString medalError = ''.obs;
  RxList<Map<String, dynamic>> medalList = <Map<String, dynamic>>[].obs;
  bool _medalListLoaded = false;

  /// 打开/关闭粉丝牌面板（点输入栏左侧按钮）
  void toggleMedalPanel() {
    final show = !showMedalPanel.value;
    showMedalPanel.value = show;
    if (show) {
      showEmotePanel.value = false;
      loadMedalList();
    }
  }

  /// 拉取粉丝牌库（含佩戴状态）
  Future<void> loadMedalList() async {
    if (_medalListLoaded || medalLoading.value) return;
    if (userId == 0) {
      medalError.value = '登录后可管理粉丝牌';
      return;
    }
    medalLoading.value = true;
    medalError.value = '';
    try {
      final medals = await LiveHttp.fansMedalList();
      if (medals.isEmpty) {
        medalError.value = '暂无粉丝牌';
      } else {
        medalList.assignAll(medals);
        _medalListLoaded = true;
      }
    } catch (e) {
      medalError.value = '粉丝牌获取失败: $e';
    } finally {
      medalLoading.value = false;
    }
  }

  /// 刷新粉丝牌库（下拉/重试）
  Future<void> refreshMedalList() async {
    _medalListLoaded = false;
    medalList.clear();
    await loadMedalList();
  }

  /// 面板中手动佩戴某块粉丝牌
  Future<void> wearMedalFromPanel(Map<String, dynamic> medal) async {
    final medalId = medal['medal_id'] as int;
    final name = medal['medal_name']?.toString() ?? '';
    final ok = await LiveHttp.wearFansMedal(medalId: medalId, status: 1);
    if (ok) {
      // 同步面板内的佩戴标记
      for (final m in medalList) {
        m['wear'] = m['medal_id'] == medalId;
        m['status'] = m['medal_id'] == medalId ? 1 : 0;
      }
      medalList.refresh();
      // 手动换牌后视为用户当前的意愿，退出还原以这块牌为基准
      _prevWornMedalId = medalId;
      _prevWornMedalName = name;
      _autoWornMedalId = null;
      _medalToast('已佩戴粉丝牌「$name」');
    } else {
      _medalToast('佩戴粉丝牌「$name」失败');
    }
  }

  /// 面板中取下当前佩戴的粉丝牌
  Future<void> takeOffMedalFromPanel() async {
    final ok = await LiveHttp.wearFansMedal(medalId: 0, status: 0);
    if (ok) {
      for (final m in medalList) {
        m['wear'] = false;
        m['status'] = 0;
      }
      medalList.refresh();
      _prevWornMedalId = null;
      _prevWornMedalName = null;
      _autoWornMedalId = null;
      _medalToast('已取下粉丝牌');
    } else {
      _medalToast('取下粉丝牌失败');
    }
  }

  /// 离开直播间：取下自动换上的粉丝牌，并恢复此前的佩戴
  Future<void> _restoreFansMedal() async {
    final worn = _autoWornMedalId;
    final prev = _prevWornMedalId;
    final prevName = _prevWornMedalName;
    _autoWornMedalId = null;
    _prevWornMedalId = null;
    _prevWornMedalName = null;
    if (userId == 0 || worn == null) return;
    // 开关中途被关闭时不做还原（用户可能自行佩戴，避免覆盖）
    final enabled = setting.get(SettingBoxKey.autoWearFansMedal,
        defaultValue: true) as bool;
    if (!enabled) return;
    try {
      if (prev != null && prev != worn) {
        // 恢复之前佩戴的另一块粉丝牌
        final ok = await LiveHttp.wearFansMedal(medalId: prev, status: 1);
        if (ok) {
          _medalToast('已还原粉丝牌${prevName != null ? '「$prevName」' : ''}');
        }
      } else {
        // 之前没佩戴（或戴的就是这块）：取下
        final ok = await LiveHttp.wearFansMedal(medalId: 0, status: 0);
        if (ok) {
          _medalToast('已取下粉丝牌，恢复未佩戴状态');
        }
      }
    } catch (_) {}
  }

  // 修改画质
  void changeQn(int qn) async {
    tempCurrentQn = currentQn;
    if (currentQn == qn) {
      return;
    }
    currentQn = qn;
    currentQnDesc.value = LiveQuality.values
        .firstWhere((element) => element.code == currentQn)
        .description;
    await queryLiveInfo();
  }

  void flushPendingDanmaku() {
    if (danmakuController == null || _pendingDanmakuItems.isEmpty) return;
    danmakuController!.addItems(_pendingDanmakuItems);
    _pendingDanmakuItems.clear();
  }

  Future<void> loadLiveEmotes() async {
    if (_emotesLoaded || emoteLoading.value) return;
    emoteLoading.value = true;
    emoteError.value = '';
    try {
      final res = await LiveHttp.getLiveEmoticons(roomId: roomId);
      if (res['status'] == true) {
        emotePackages.assignAll(
          (res['data'] as List).cast<LiveEmotePackage>(),
        );
        _emotesLoaded = true;
      } else {
        emoteError.value = res['msg']?.toString() ?? '获取直播间表情失败';
      }
    } catch (e) {
      emoteError.value = '获取直播间表情失败: $e';
    } finally {
      emoteLoading.value = false;
    }
  }

  void insertLiveEmote(LiveEmote emote) {
    final text = emote.emoji ?? emote.unique ?? '';
    if (text.isEmpty) return;
    final selection = inputController.selection;
    final cursor = selection.isValid && selection.baseOffset >= 0
        ? selection.baseOffset
        : inputController.text.length;
    final current = inputController.text;
    final safeCursor = cursor.clamp(0, current.length);
    inputController.value = TextEditingValue(
      text:
          '${current.substring(0, safeCursor)}$text${current.substring(safeCursor)}',
      selection: TextSelection.collapsed(offset: safeCursor + text.length),
    );
  }

  Future<void> sendLiveEmote(LiveEmote emote) async {
    final unique = emote.unique;
    if (unique == null || unique.isEmpty) return;
    sendStatus.value = '发送中';
    final res = await LiveHttp.sendDanmaku(
      roomId: roomId,
      msg: unique,
      dmType: 1,
      emoticonOptions: '[object Object]',
    );
    if (res['status']) {
      sendStatus.value = '已提交，等待直播间回流确认';
      showEmotePanel.value = false;
      SmartDialog.showToast('表情已提交，等待直播间回流确认');
    } else {
      sendStatus.value = '发送失败';
      SmartDialog.showToast(res['msg'] ?? '表情发送失败');
    }
  }

  Future<void> sendMsg() async {
    final msg = inputController.text.trim();
    if (msg.isEmpty) return;
    sendStatus.value = '发送中';
    final res = await LiveHttp.sendDanmaku(roomId: roomId, msg: msg);
    if (res['status']) {
      inputController.clear();
      sendStatus.value = '已提交，等待弹幕回流确认';
      SmartDialog.showToast('弹幕已提交，等待直播间回流确认');
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (sendStatus.value == '已提交，等待弹幕回流确认') {
          sendStatus.value = '未收到回流，请检查连接';
          SmartDialog.showToast('弹幕接口已接受，但暂未收到直播回流');
        }
      });
    } else {
      sendStatus.value = '发送失败';
      SmartDialog.showToast(res['msg'] ?? '弹幕发送失败');
    }
  }

  // 历史记录
  void heartBeat() {
    LiveHttp.liveRoomEntry(roomId: roomId);
  }

  @override
  void onClose() {
    heartBeat();
    unawaited(_restoreFansMedal());
    closeLiveMsg();
    _playerErrorSub?.cancel();
    _stallWatchdog?.cancel();
    _pendingDanmakuItems.clear();
    messageList.clear();
    inputController.dispose();
    super.onClose();
  }
}
