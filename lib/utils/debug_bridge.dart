import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../http/danmaku.dart';
import 'simple_mode_service.dart';
import '../http/reply.dart';
import '../http/search.dart';
import '../models/danmaku/dm.pb.dart';
import '../pages/live_room/controller.dart';
import '../pages/search/controller.dart';
import '../plugin/pl_player/index.dart';
import '../utils/id_utils.dart';
import '../utils/utils.dart';
import 'storage.dart';

/// ADB 调试桥：统一的 adb 注入接口。
///
/// 所有命令通过 Android broadcast 发出，native 侧统一转发到本类的 action 注册表：
/// ```sh
/// adb shell am broadcast -a com.Zeitlind.bill.DEBUG_<COMMAND> [--ei key int] [--es key str]
/// ```
///
/// 安全性：
/// - release 构建下整个接收器不注册，任何注入均不生效；
/// - debug 构建下还需在「设置 → 调试模式」中打开总开关（默认关闭）。
///
/// 响应统一以 `ADB_RSP` 前缀写入 logcat（tag=flutter），并带请求序号 `seq`。
class DebugBridge {
  DebugBridge._();

  static final DebugBridge instance = DebugBridge._();

  static const String _tag = 'DebugBridge';
  static const EventChannel _events =
      EventChannel('com.Zeitlind.bill/debug_events');

  /// 设置项：ADB 注入总开关
  static const String kAdbInjectEnabled = 'adbInjectEnabled';

  int _seq = 0;

  /// 语义树开关句柄：GET_UI_TREE 首次调用时启用，进程内保持。
  /// Flutter 默认不构建语义树（除非平台辅助功能开启），需要主动 ensure。
  SemanticsHandle? _semanticsHandle;

  Map<String, DebugCommandHandler> _registry = {};

  /// 命令注册表：native action 后缀 -> 处理器。
  /// 新增命令只需在 [registerDefaults] 加一项，native 侧无需再改。
  void _registerDefaults() {
    _registry = {
      'PING': _handlePing,
      'GET_AUDIO_MODE': _handleGetAudioMode,
      'SET_AUDIO_MODE': _handleSetAudioMode,
      'GOTO_LIVE_ROOM': _handleGotoLiveRoom,
      'GOTO_VIDEO': _handleGotoVideo,
      'GET_COMMENTS': _handleGetComments,
      'GET_DANMAKU': _handleGetDanmaku,
      'GET_LIVE_DANMAKU': _handleGetLiveDanmaku,
      'GET_CURRENT_STATE': _handleGetCurrentState,
      'GET_UI_TREE': _handleGetUiTree,
      'TAP_NODE': _handleTapNode,
      'SHOW_CONTROLS': _handleShowControls,
      'SET_PLAYBACK_SPEED': _handleSetPlaybackSpeed,
      'GOTO_PAGE': _handleGotoPage,
      'SET_SIMPLE_MODE': _handleSetSimpleMode,
    };
  }

  /// 初始化：监听 native 侧转发的 broadcast。
  /// 仅 debug 构建调用（native 侧同样仅在 debug 构建注册 receiver）。
  void init() {
    _registerDefaults();
    _events.receiveBroadcastStream().listen(_onEvent, onError: (e) {
      debugPrint('$_tag stream error: $e');
    });
    debugPrint(
        '$_tag initialized (debug build, registry=${_registry.keys.length} commands)');
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final Map<dynamic, dynamic> map = event;
    final String cmd = map['cmd']?.toString() ?? '';
    if (cmd == 'READY') return; // native 就绪信号，非用户命令
    final int seq = _seq++;
    debugPrint('$_tag <- cmd=$cmd seq=$seq payload=$map');

    // 门控：除 PING 外全部需要开关
    final bool enabled = cmd == 'PING' || _adbInjectEnabled;
    if (!enabled) {
      _respond(seq, cmd, ok: false, error: 'ADB 注入未开启（设置 → 调试模式）');
      return;
    }

    final handler = _registry[cmd];
    if (handler == null) {
      _respond(seq, cmd,
          ok: false, error: '未知命令 $cmd，可用: ${_registry.keys.join(",")}');
      return;
    }
    handler(map, seq);
  }

  // ============ 门控 ============

  Box<dynamic> get _setting => GStrorage.setting;

  bool get _adbInjectEnabled =>
      _setting.get(kAdbInjectEnabled, defaultValue: false) == true;

  // ============ 工具 ============

  void _respond(int seq, String cmd,
      {bool ok = true, Object? error, Object? data}) {
    final payload = jsonEncode({
      'seq': seq,
      'cmd': cmd,
      'ok': ok,
      if (error != null) 'error': error.toString(),
      if (data != null) 'data': data,
    });
    // Android logcat 单条消息截断在 ~1000 字符（tag+内容），
    // 超长响应（如 GET_UI_TREE）会静默丢失节点。分段打印：
    // ADB_RSP {"seq":..,"cmd":..,"ok":..,"data":{...,"chunk":"1/3","chunks":3}}
    const int maxChunk = 900;
    if (payload.length <= maxChunk) {
      debugPrint('ADB_RSP $payload');
      return;
    }
    final int chunks = (payload.length / maxChunk).ceil();
    for (int i = 0; i < chunks; i++) {
      final int start = i * maxChunk;
      final int end = (start + maxChunk) > payload.length
          ? payload.length
          : start + maxChunk;
      // 分段标记放在行首便于拼接：ADB_RSP_CHUNK i/total <片段>
      debugPrint(
          'ADB_RSP_CHUNK ${i + 1}/$chunks ${payload.substring(start, end)}');
    }
  }

  int? _intArg(Map map, String key) => int.tryParse('${map[key]}');
  String? _strArg(Map map, String key) => map[key]?.toString();
  double? _doubleArg(Map map, String key) =>
      double.tryParse('${map[key]}'.replaceAll(',', '.'));

  bool _boolArg(Map map, String key, {bool defaultValue = false}) {
    final v = map[key];
    if (v == null) return defaultValue;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  // ============ 命令实现 ============

  Future<void> _handlePing(Map map, int seq) async {
    _respond(seq, 'PING',
        data: {'pong': true, 'commands': _registry.keys.toList()});
  }

  Future<void> _handleGetAudioMode(Map map, int seq) async {
    final enabled =
        _setting.get(SettingBoxKey.enableAudioMode, defaultValue: false);
    _respond(seq, 'GET_AUDIO_MODE',
        data: {'audioMode': enabled == true ? 1 : 0});
  }

  Future<void> _handleSetAudioMode(Map map, int seq) async {
    final enable = map['enable'] == true || map['enable'] == 1;
    await _setting.put(SettingBoxKey.enableAudioMode, enable);
    _respond(seq, 'SET_AUDIO_MODE', data: {'audioMode': enable ? 1 : 0});
  }

  Future<void> _handleGotoLiveRoom(Map map, int seq) async {
    final roomId = _intArg(map, 'roomId');
    if (roomId == null || roomId <= 0) {
      _respond(seq, 'GOTO_LIVE_ROOM', ok: false, error: '缺少/非法 roomId');
      return;
    }
    if (Get.context == null) {
      _respond(seq, 'GOTO_LIVE_ROOM', ok: false, error: '导航不可用（无 context）');
      return;
    }
    Get.toNamed<dynamic>(
      '/liveRoom?roomid=$roomId',
      arguments: <String, String?>{
        'liveItem': null,
        'heroTag': roomId.toString(),
      },
    );
    _respond(seq, 'GOTO_LIVE_ROOM', data: {'roomId': roomId});
  }

  /// 跳转到指定路由（如 /setting /fav 等）
  Future<void> _handleGotoPage(Map map, int seq) async {
    final route = _strArg(map, 'route');
    if (route == null || route.trim().isEmpty) {
      _respond(seq, 'GOTO_PAGE', ok: false, error: '缺少 --es route <路由>');
      return;
    }
    Get.toNamed(route);
    _respond(seq, 'GOTO_PAGE', data: {'route': route});
  }

  /// 切换极简模式（测试用）
  Future<void> _handleSetSimpleMode(Map map, int seq) async {
    final String? flag = _strArg(map, 'enabled');
    final bool? enabled = flag == null ? null : flag == 'true' || flag == '1';
    final svc = Get.isRegistered<SimpleModeService>()
        ? SimpleModeService.instance
        : null;
    if (svc == null) {
      _respond(seq, 'SET_SIMPLE_MODE', ok: false, error: 'SimpleModeService 未注册');
      return;
    }
    if (enabled != null) {
      await svc.setEnabled(enabled);
    }
    _respond(seq, 'SET_SIMPLE_MODE', data: {
      'enabled': svc.enabled.value,
      'autoOn': svc.autoOnTime.value,
      'autoOff': svc.autoOffTime.value,
    });
  }

  Future<void> _handleGotoVideo(Map map, int seq) async {
    final bvid = _strArg(map, 'bvid');
    if (bvid == null || bvid.trim().isEmpty) {
      _respond(seq, 'GOTO_VIDEO', ok: false, error: '缺少 bvid');
      return;
    }
    // BV 号 body 为大小写敏感的 base58，仅规范前缀，不可整体 toUpperCase
    final normalized = _normalizeBvid(bvid.trim());
    final aid = IdUtils.bv2av(normalized);
    final cid = await SearchHttp.ab2c(bvid: normalized);
    if (cid <= 0) {
      _respond(seq, 'GOTO_VIDEO',
          ok: false, error: 'bvid 转 cid 失败: $normalized');
      return;
    }
    if (Get.context == null) {
      _respond(seq, 'GOTO_VIDEO', ok: false, error: '导航不可用（无 context）');
      return;
    }
    final heroTag = Utils.makeHeroTag(aid);
    Get.toNamed<dynamic>(
      '/video?bvid=$normalized&cid=$cid',
      arguments: <String, String?>{'pic': '', 'heroTag': heroTag},
    );
    _respond(seq, 'GOTO_VIDEO',
        data: {'bvid': normalized, 'aid': aid, 'cid': cid});
  }

  /// 规范 BV 号：统一 "BV" 前缀大小写，body（base58）保持原样。
  String _normalizeBvid(String raw) {
    var s = raw.trim();
    if (s.length >= 2) {
      final prefix = s.substring(0, 2);
      if (prefix.toUpperCase() == 'BV') {
        s = 'BV${s.substring(2)}';
      }
    }
    return s;
  }

  /// 读取当前页面评论：优先返回当前视频页/直播间内存中的评论；
  /// 也可显式传 bvid + page 主动拉取。
  Future<void> _handleGetComments(Map map, int seq) async {
    final bvidRaw = _strArg(map, 'bvid');
    final bvid = (bvidRaw == null || bvidRaw.trim().isEmpty)
        ? null
        : _normalizeBvid(bvidRaw.trim());
    final page = _intArg(map, 'page') ?? 1;
    final count = _intArg(map, 'count') ?? 20;

    // 1) 显式 bvid：拉取该视频评论
    if (bvid != null && bvid.isNotEmpty) {
      final aid = IdUtils.bv2av(bvid);
      final res = await ReplyHttp.replyList(oid: aid, pageNum: page, type: 1);
      _respond(seq, 'GET_COMMENTS',
          data: _formatReplyResult(res, count, source: 'bvid:$bvid'));
      return;
    }

    // 2) 当前正在直播页：返回弹幕消息列表（直播没有传统“评论”）
    if (Get.isRegistered<LiveRoomController>()) {
      final ctr = Get.find<LiveRoomController>();
      final items = ctr.messageList
          .take(count)
          .map((m) => {
                'user': m.userName,
                'message': m.message,
              })
          .toList();
      _respond(seq, 'GET_COMMENTS', data: {
        'source': 'liveRoom:${ctr.roomId}',
        'count': items.length,
        'comments': items,
      });
      return;
    }

    _respond(seq, 'GET_COMMENTS',
        ok: false, error: '当前页面无评论数据；请传 --es bvid <BV号> 或先进入视频页');
  }

  Map _formatReplyResult(dynamic res, int count, {String? source}) {
    if (res['status'] != true) {
      return {'source': source, 'error': res['msg']?.toString() ?? '请求失败'};
    }
    final data = res['data'];
    final replies = (data?.replies as List?) ?? const [];
    final items = replies.take(count).map((r) {
      return {
        'user': r.member?.uname ?? '',
        'like': r.like ?? 0,
        'ctime': r.ctime ?? 0,
        'message': r.content?.message ?? '',
      };
    }).toList();
    return {
      'source': source,
      'total': data?.page?.acount ?? items.length,
      'count': items.length,
      'comments': items,
    };
  }

  /// 读取当前视频弹幕：需要当前处于视频页（取 cid），
  /// 或显式传 --ei cid <cid> --ei segment <段号，1 起>。
  Future<void> _handleGetDanmaku(Map map, int seq) async {
    final cidArg = _intArg(map, 'cid');
    final segment = _intArg(map, 'segment') ?? 1;
    final count = _intArg(map, 'count') ?? 30;

    int? cid = cidArg;
    if (cid == null || cid <= 0) {
      // 从当前视频页控制器取 cid
      try {
        final vdCtr = Get.find<dynamic>(tag: Get.arguments?['heroTag'] ?? '');
        cid = vdCtr?.cid?.value;
      } catch (_) {
        cid = null;
      }
    }
    if (cid == null || cid <= 0) {
      _respond(seq, 'GET_DANMAKU',
          ok: false, error: '缺少/非法 cid；请传 --ei cid <cid> 或先进入视频页');
      return;
    }

    final DmSegMobileReply result =
        await DanmakaHttp.queryDanmaku(cid: cid, segmentIndex: segment);
    final elems = result.elems
        .take(count)
        .map((e) => {
              'progress': e.progress,
              'mode': e.mode,
              'fontsize': e.fontsize,
              'color': e.color,
              'text': e.content,
            })
        .toList();
    _respond(seq, 'GET_DANMAKU', data: {
      'cid': cid,
      'segment': segment,
      'count': elems.length,
      'danmaku': elems,
    });
  }

  /// 读取当前直播间弹幕（实时消息列表内存数据）。
  Future<void> _handleGetLiveDanmaku(Map map, int seq) async {
    final count = _intArg(map, 'count') ?? 30;
    if (!Get.isRegistered<LiveRoomController>()) {
      _respond(seq, 'GET_LIVE_DANMAKU', ok: false, error: '当前不在直播间');
      return;
    }
    final ctr = Get.find<LiveRoomController>();
    final items = ctr.messageList
        .take(count)
        .map((m) => {
              'user': m.userName,
              'message': m.message,
            })
        .toList();
    _respond(seq, 'GET_LIVE_DANMAKU', data: {
      'roomId': ctr.roomId,
      'count': items.length,
      'danmaku': items,
    });
  }

  /// 读取当前所处页面状态：路由 + 页面上下文（视频/直播/搜索/专栏等）。
  Future<void> _handleGetCurrentState(Map map, int seq) async {
    String route = Get.currentRoute;

    // 规范化：GetX 路由可能带完整 query（/video?bvid=xx&cid=xx），拆出参数
    String path = route;
    Map<String, String> params = {};
    final qIdx = route.indexOf('?');
    if (qIdx >= 0) {
      path = route.substring(0, qIdx);
      final query = route.substring(qIdx + 1);
      for (final pair in query.split('&')) {
        final kv = pair.split('=');
        if (kv.length == 2) {
          params[Uri.decodeComponent(kv[0])] = Uri.decodeComponent(kv[1]);
        }
      }
    }

    final state = <String, dynamic>{
      'route': path,
      'params': params.isEmpty ? null : params,
    };

    switch (path) {
      case '/video':
        state['page'] = 'video';
        state['bvid'] = params['bvid'];
        state['cid'] = params['cid'];
        _appendPlayerResolution(state);
        break;
      case '/liveRoom':
        state['page'] = 'liveRoom';
        state['roomId'] = params['roomid'];
        if (Get.isRegistered<LiveRoomController>()) {
          final ctr = Get.find<LiveRoomController>();
          state['roomId'] = ctr.roomId;
          state['title'] = ctr.roomInfoH5.value.roomInfo?.title;
          state['anchor'] = ctr.roomInfoH5.value.anchorInfo?.baseInfo?.uname;
          state['liveStatus'] =
              ctr.roomInfoH5.value.roomInfo?.liveStatus?.toString();
          // 直播流方向：服务端 isPortrait 标记（竖屏直播间）
          final isPortraitLive = ctr.isPortrait.value;
          state['streamOrientation'] =
              isPortraitLive ? 'portrait' : 'landscape';
        }
        _appendPlayerResolution(state);
        break;
      case '/searchResult':
      case '/search':
        state['page'] = 'search';
        state['keyword'] = params['keyword'];
        try {
          if (Get.isRegistered<SSearchController>()) {
            final ctr = Get.find<SSearchController>();
            state['keyword'] = ctr.searchKeyWord.value;
          }
        } catch (_) {}
        break;
      case '/opus':
      case '/read':
        state['page'] = 'article';
        state['id'] = params['id'];
        state['title'] = params['title'];
        state['articleType'] = params['articleType'];
        break;
      case '/dynamicDetail':
        state['page'] = 'dynamic';
        state['id'] = params['id'];
        break;
      case '/':
        state['page'] = 'home';
        break;
      default:
        final seg = path.split('/').where((s) => s.isNotEmpty).join('/');
        state['page'] = seg.isEmpty ? 'home' : seg;
        break;
    }

    _respond(seq, 'GET_CURRENT_STATE', data: state);
  }

  /// 从当前播放器读取实际视频分辨率与画面方向（视频/直播通用）。
  /// audioOnly 时无视频轨，宽度/高度可能为 null。
  void _appendPlayerResolution(Map<String, dynamic> state) {
    try {
      // PlPlayerController 是单例；videoType 'none' 不递增计数，纯读取用
      final plc = PlPlayerController(videoType: 'none');
      final player = plc.videoPlayerController;
      if (player == null) return;
      final w = player.state.width;
      final h = player.state.height;
      if (w != null && h != null && w > 0 && h > 0) {
        state['videoWidth'] = w;
        state['videoHeight'] = h;
        state['resolution'] = '${w}x$h';
        state['videoOrientation'] = w >= h ? 'landscape' : 'portrait';
      } else {
        state['resolution'] = null; // 纯音频或视频轨未就绪
      }
    } catch (e) {
      state['resolutionError'] = e.toString();
    }
  }

  /// 读取当前页面的语义树：已加载控件的可点中心坐标 + 文本/类型。
  ///
  /// 背景：uiautomator dump 只能看到 Android 原生层节点，Flutter 内部
  /// 大量控件（播放器按钮、bottom sheet 选项）没有语义暴露，
  /// 自动化点击只能靠猜坐标。此命令直接从 Flutter 语义树取
  /// 带动作（点击/长按）的控件，返回屏幕坐标供 `input tap` 使用。
  ///
  /// 参数：
  /// - `--es contains <keyword>`：只返回文本包含 keyword 的控件（可选）
  /// - `--ez actionsOnly true`：只返回有点击动作的控件（默认 true）
  Future<void> _handleGetUiTree(Map map, int seq) async {
    final String? contains = _strArg(map, 'contains');
    final bool actionsOnly =
        _boolArg(map, 'actionsOnly', defaultValue: true);

    final List<Map<String, dynamic>> result = [];

    try {
      // 语义树默认不构建；首次调用时启用并保持（SemanticsHandle 释放才会关闭）
      _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
      // 语义构建是异步帧管线任务，等一帧保证树已更新到当前 UI
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final ctx = Get.key.currentContext;
      if (ctx == null) {
        _respond(seq, 'GET_UI_TREE',
            ok: false, error: '无可用 context（应用未就绪）');
        return;
      }
      // Get.key 是全局 navigator key，跨 async 读取 currentContext 安全
      // ignore: use_build_context_synchronously
      final RenderObject root = ctx.findRenderObject()!;

      void collect(SemanticsNode node, Matrix4 transform) {
        final SemanticsData data = node.getSemanticsData();
        bool match = true;
        // SemanticsData.actions 是位掩码，按 SemanticsAction.index 判断
        final bool hasTap =
            (data.actions & (1 << SemanticsAction.tap.index)) != 0;
        if (actionsOnly && !hasTap) {
          match = false;
        }
        String label = data.label;
        if (contains != null && contains.isNotEmpty) {
          if (!label.toLowerCase().contains(contains.toLowerCase())) {
            match = false;
          }
        }
        if (match) {
          // rect 变换到全局坐标（MatrixUtils.transformRect 要求仿射矩阵）
          Rect rect = node.rect;
          try {
            rect = MatrixUtils.transformRect(transform, rect);
          } catch (_) {
            // transform 非仿射时保留局部坐标
          }
          final List<String> actionNames = <String>[];
          for (final SemanticsAction a in SemanticsAction.values) {
            if ((data.actions & (1 << a.index)) != 0) {
              actionNames.add(a.name);
            }
          }
          result.add(<String, dynamic>{
            'id': node.id,
            'label': label,
            'hint': data.hint,
            'x': (rect.center.dx).round(),
            'y': (rect.center.dy).round(),
            'w': rect.width.round(),
            'h': rect.height.round(),
            'actions': actionNames,
          });
        }
      }

      void walk(SemanticsNode node, Matrix4 parentTransform) {
        // 节点 rect 是父坐标系；transform 变换到全局（屏幕）坐标
        final Matrix4 transform = parentTransform.clone();
        if (node.transform != null) {
          transform.multiply(node.transform!);
        }
        node.visitChildren((SemanticsNode child) {
          walk(child, transform);
          return true;
        });
        collect(node, transform);
      }

      // 顶层：通过 PipelineOwner 拿根语义节点
      final pipelineOwner = root.owner;
      SemanticsNode? rootNode;
      if (pipelineOwner is PipelineOwner) {
        rootNode = pipelineOwner.semanticsOwner?.rootSemanticsNode;
      }
      if (rootNode == null) {
        _respond(seq, 'GET_UI_TREE',
            ok: false, error: '语义树不可用（semantics disabled）');
        return;
      }
      walk(rootNode, Matrix4.identity());

      _respond(seq, 'GET_UI_TREE', data: {
        'route': Get.currentRoute,
        'count': result.length,
        'nodes': result,
      });
    } catch (e) {
      _respond(seq, 'GET_UI_TREE', ok: false, error: e.toString());
    }
  }

  /// 获取语义根节点（语义树未启用则先启用）。
  Future<SemanticsNode?> _obtainSemanticsRoot() async {
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final ctx = Get.key.currentContext;
    if (ctx == null) return null;
    // ignore: use_build_context_synchronously
    final RenderObject root = ctx.findRenderObject()!;
    final pipelineOwner = root.owner;
    if (pipelineOwner is PipelineOwner) {
      return pipelineOwner.semanticsOwner?.rootSemanticsNode;
    }
    return null;
  }

  /// 直接对语义节点派发动作（tap/longPress），无需坐标模拟点击。
  ///
  /// 这是比「GET_UI_TREE 取坐标 + input tap」更可靠的方式：
  /// 坐标会被遮挡层/滚动偏移干扰，而 performAction 直接调用控件注册的
  /// 语义动作处理器，等效于无障碍服务点击，不受遮挡与坐标漂移影响。
  ///
  /// 定位方式（二选一）：
  /// - `--ei id <id>`：GET_UI_TREE 返回的节点 id（精确）
  /// - `--es label <文本>`：文本匹配（contains，取第一个匹配且支持该动作的节点）
  ///
  /// 动作：`--es action tap|longPress`（默认 tap）
  Future<void> _handleTapNode(Map map, int seq) async {
    final int? id = _intArg(map, 'id');
    final String? label = _strArg(map, 'label');
    final String action = (_strArg(map, 'action') ?? 'tap').toLowerCase();

    SemanticsAction? semAction;
    switch (action) {
      case 'tap':
        semAction = SemanticsAction.tap;
        break;
      case 'longpress':
        semAction = SemanticsAction.longPress;
        break;
      default:
        _respond(seq, 'TAP_NODE',
            ok: false, error: '不支持的动作 $action（可用: tap / longPress）');
        return;
    }

    if (id == null && (label == null || label.isEmpty)) {
      _respond(seq, 'TAP_NODE',
          ok: false, error: '缺少定位参数：--ei id <id> 或 --es label <文本>');
      return;
    }

    try {
      final SemanticsNode? root = await _obtainSemanticsRoot();
      if (root == null) {
        _respond(seq, 'TAP_NODE', ok: false, error: '语义树不可用');
        return;
      }

      // 找目标节点
      SemanticsNode? target;
      if (id != null) {
        void findById(SemanticsNode node) {
          if (target != null) return;
          if (node.id == id) {
            target = node;
            return;
          }
          node.visitChildren((SemanticsNode child) {
            findById(child);
            return target == null;
          });
        }

        findById(root);
      } else {
        final String lower = label!.toLowerCase();
        bool supports(SemanticsNode node) =>
            (node.getSemanticsData().actions &
                    (1 << semAction!.index)) !=
            0;

        void findByLabel(SemanticsNode node) {
          if (target != null) return;
          final String l = node.getSemanticsData().label;
          if (l.toLowerCase().contains(lower) && supports(node)) {
            target = node;
            return;
          }
          node.visitChildren((SemanticsNode child) {
            findByLabel(child);
            return target == null;
          });
        }

        findByLabel(root);
      }

      if (target == null) {
        _respond(seq, 'TAP_NODE',
            ok: false,
            error: id != null
                ? '未找到 id=$id 的节点（UI 可能已变化，请重新 GET_UI_TREE）'
                : '未找到文本含 "$label" 且支持 $action 的节点');
        return;
      }

      // 派发动作：直接走语义处理器（SemanticsNode 自身无公开 performAction，
      // 走 SemanticsOwner.performAction(id, action)）
      // ignore: use_build_context_synchronously
      final RenderObject rootRo = Get.key.currentContext!.findRenderObject()!;
      final PipelineOwner po = rootRo.owner as PipelineOwner;
      po.semanticsOwner!.performAction(target!.id, semAction);

      _respond(seq, 'TAP_NODE', data: {
        'id': target!.id,
        'label': target!.getSemanticsData().label,
        'action': action,
      });
    } catch (e) {
      _respond(seq, 'TAP_NODE', ok: false, error: e.toString());
    }
  }

  /// 强制显示播放器控制条（隐藏控件进入语义树的前提）。
  ///
  /// 背景：播放器控制条（播放/进度/倍速/全屏等）依赖 showControls 显示，
  /// 隐藏时这些按钮不在语义树中，GET_UI_TREE 查不到、TAP_NODE 也无法派发。
  /// 本命令把控制条置为可见并取消自动隐藏定时器，seconds 秒后恢复自动隐藏，
  /// 期间可用 GET_UI_TREE 枚举 / TAP_NODE 直接派发。
  ///
  /// 参数：--ei seconds <保持秒数>（默认 10）
  Future<void> _handleShowControls(Map map, int seq) async {
    final int seconds = _intArg(map, 'seconds') ?? 10;
    try {
      final plc = PlPlayerController(videoType: 'none');
      if (plc.videoPlayerController == null) {
        _respond(seq, 'SHOW_CONTROLS',
            ok: false, error: '当前无播放器实例（需先进入视频/直播/离线播放页）');
        return;
      }
      // controls=true 会启动 3s 自动隐藏定时器，随后取消它保持常显
      plc.controls = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      plc.cancelControlsHideTimer();
      if (seconds > 0) {
        Future<void>.delayed(Duration(seconds: seconds)).then((_) {
          try {
            // 到期重新走一次显示→自动隐藏流程
            plc.controls = true;
          } catch (_) {}
        });
      }
      // 等一帧让语义树更新
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _respond(seq, 'SHOW_CONTROLS', data: {
        'showing': true,
        'seconds': seconds,
        'hint': '控制条已显示，此期间可用 GET_UI_TREE 枚举 / TAP_NODE 派发',
      });
    } catch (e) {
      _respond(seq, 'SHOW_CONTROLS', ok: false, error: e.toString());
    }
  }

  /// 直接设置播放倍速（无需 UI 操作）。
  ///
  /// 参数：--ed speed <倍速>（支持小数，如 2.0 / 1.5 / 0.5；超出 speedsList 也允许）
  Future<void> _handleSetPlaybackSpeed(Map map, int seq) async {
    final double? speed = _doubleArg(map, 'speed');
    if (speed == null || speed <= 0 || speed > 16) {
      _respond(seq, 'SET_PLAYBACK_SPEED',
          ok: false, error: '缺少或非法 speed（--ed speed 2.0，范围 0~16）');
      return;
    }
    try {
      final plc = PlPlayerController(videoType: 'none');
      if (plc.videoPlayerController == null) {
        _respond(seq, 'SET_PLAYBACK_SPEED',
            ok: false, error: '当前无播放器实例（需先进入视频/直播/离线播放页）');
        return;
      }
      await plc.setPlaybackSpeed(speed);
      _respond(seq, 'SET_PLAYBACK_SPEED', data: {
        'speed': speed,
      });
    } catch (e) {
      _respond(seq, 'SET_PLAYBACK_SPEED', ok: false, error: e.toString());
    }
  }
}

/// 命令处理器签名：收 native 转发的 payload（含命令参数）与响应序号。
typedef DebugCommandHandler = Future<void> Function(
    Map<dynamic, dynamic> map, int seq);
