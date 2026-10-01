import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/msg.dart';
import 'package:pilipala/models/msg/session.dart';
import 'package:pilipala/pages/whisper/index.dart';
import '../../utils/feed_back.dart';
import '../../utils/storage.dart';

class WhisperDetailController extends GetxController {
  int? talkerId;
  late String name;
  late String face;
  late String mid;
  late String heroTag;
  RxList<MessageItem> messageList = <MessageItem>[].obs;
  //表情转换图片规则
  RxList<dynamic> eInfos = [].obs;
  final TextEditingController replyContentController = TextEditingController();
  Box userInfoCache = GStrorage.userInfo;
  List emoteList = [];
  List<String> picList = [];

  @override
  void onInit() {
    super.onInit();
    if (Get.parameters.containsKey('talkerId')) {
      talkerId = int.parse(Get.parameters['talkerId']!);
    } else {
      talkerId = int.parse(Get.parameters['mid']!);
    }
    name = Get.parameters['name']!;
    face = Get.parameters['face']!;
    mid = Get.parameters['mid']!;
    heroTag = Get.parameters['heroTag']!;
  }

  Future querySessionMsg() async {
    var res = await MsgHttp.sessionMsg(talkerId: talkerId);
    if (res['status']) {
      messageList.value = res['data'].messages;
      // 找出图片（content 可能是 Map，也可能是字符串，需类型兼容）
      try {
        for (var item in messageList) {
          if (item.msgType != 2) continue;
          final dynamic c = item.content;
          if (c is Map && c['url'] is String) {
            picList.add(c['url'] as String);
          }
        }
        picList = picList.reversed.toList();
      } catch (e) {
        debugPrint('querySessionMsg collect pics: $e');
      }

      if (messageList.isNotEmpty) {
        ackSessionMsg();
        if (res['data'].eInfos != null) {
          eInfos.value = res['data'].eInfos;
        }
      }
    } else {
      SmartDialog.showToast(res['msg']);
    }
    return res;
  }

  // 消息标记已读
  Future ackSessionMsg() async {
    if (messageList.isEmpty) {
      return;
    }
    await MsgHttp.ackSessionMsg(
      talkerId: talkerId,
      ackSeqno: messageList.last.msgSeqno,
    );
  }

  Future sendMsg() async {
    feedBack();
    String message = replyContentController.text;
    final userInfo = userInfoCache.get('userInfoCache');
    if (userInfo == null) {
      SmartDialog.showToast('请先登录');
      return;
    }
    if (message == '') {
      SmartDialog.showToast('请输入内容');
      return;
    }
    var result = await MsgHttp.sendMsg(
      senderUid: userInfo.mid,
      receiverId: int.parse(mid),
      content: {'content': message},
      msgType: 1,
    );
    if (result['status']) {
      String content = jsonDecode(result['data']['msg_content'])['content'];
      messageList.insert(
        0,
        MessageItem(
          msgSeqno: result['data']['msg_key'],
          senderUid: userInfo.mid,
          receiverId: int.parse(mid),
          content: {'content': content},
          msgType: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      eInfos.addAll(emoteList);
      replyContentController.clear();
      try {
        late final WhisperController whisperController =
            Get.find<WhisperController>();
        whisperController.refreshLastMsg(talkerId!, message);
      } catch (_) {}
    } else {
      SmartDialog.showToast(result['msg']);
    }
  }

  bool _isSending = false;

  /// 发送图片：选图 → BFS 上传(biz=im) → 以 msg_type=2 发送图片消息
  ///（对齐 piliplus 的实现）
  Future<void> sendImage() async {
    feedBack();
    final userInfo = userInfoCache.get('userInfoCache');
    if (userInfo == null) {
      SmartDialog.showToast('请先登录');
      return;
    }
    if (_isSending) return;
    _isSending = true;
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) {
        return;
      }
      final String path = picked.path;

      SmartDialog.showLoading(msg: '正在上传图片');
      final upRes = await MsgHttp.uploadBfs(path: path, biz: 'im');
      if (upRes['status'] != true) {
        SmartDialog.dismiss();
        SmartDialog.showToast(upRes['msg'] ?? '图片上传失败');
        return;
      }
      final data = upRes['data'];
      // 官方 web 端图片消息的 content 结构（数值字段统一转 int，
      // 服务器返回的字段可能是字符串，直接透传会导致对端解析/渲染类型错误）
      final List<String>? mimeParts = lookupMimeType(path)?.split('/');
      final String mimeType =
          (mimeParts != null && mimeParts.length > 1) ? mimeParts[1] : 'jpg';
      final Map<String, dynamic> picMsg = {
        'url': data['image_url'],
        'height': (num.tryParse('${data['image_height']}') ?? 1).toInt(),
        'width': (num.tryParse('${data['image_width']}') ?? 1).toInt(),
        'imageType': mimeType,
        'original': 1,
        'size': (num.tryParse('${data['img_size']}') ?? 0).toInt(),
      };
      SmartDialog.showLoading(msg: '正在发送');
      final result = await MsgHttp.sendMsg(
        senderUid: userInfo.mid,
        receiverId: int.parse(mid),
        content: picMsg,
        msgType: 2,
      );
      SmartDialog.dismiss();
      if (result['status'] == true) {
        // 本地立即插入一条图片消息（与服务器返回结构保持一致）
        messageList.insert(
          0,
          MessageItem(
            senderUid: userInfo.mid,
            receiverId: int.parse(mid),
            content: picMsg,
            msgType: 2,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
        );
        picList.insert(0, picMsg['url']);
        try {
          late final WhisperController whisperController =
              Get.find<WhisperController>();
          whisperController.refreshLastMsg(talkerId!, '[图片]');
        } catch (_) {}
        SmartDialog.showToast('发送成功');
      } else {
        SmartDialog.showToast(result['msg'] ?? '发送失败');
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
    } finally {
      _isSending = false;
    }
  }

  void removeSession(context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          clipBehavior: Clip.hardEdge,
          title: const Text('提示'),
          content: const Text('确认清空会话内容并移除会话？'),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () async {
                var res = await MsgHttp.removeSession(talkerId: talkerId);
                if (res['status']) {
                  SmartDialog.showToast('操作成功');
                  try {
                    late final WhisperController whisperController =
                        Get.find<WhisperController>();
                    whisperController.removeSessionMsg(talkerId!);
                    Get.back();
                  } catch (_) {}
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }
}
