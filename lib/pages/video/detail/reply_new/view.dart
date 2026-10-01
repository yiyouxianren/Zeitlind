import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pilipala/http/dynamics.dart';
import 'package:pilipala/http/msg.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/common/reply_type.dart';
import 'package:pilipala/models/video/reply/emote.dart';
import 'package:pilipala/models/video/reply/item.dart';
import 'package:pilipala/pages/emote/index.dart';
import 'package:pilipala/plugin/pl_player/index.dart';
import 'package:pilipala/utils/feed_back.dart';

import 'mention_panel.dart';
import 'toolbar_icon_button.dart';

class VideoReplyNewDialog extends StatefulWidget {
  final int? oid;
  final int? root;
  final int? parent;
  final ReplyType? replyType;
  final ReplyItemModel? replyItem;

  /// 视频详情页的 heroTag：用于读取播放器状态（视频进度/截图）
  final String? heroTag;

  const VideoReplyNewDialog({
    super.key,
    this.oid,
    this.root,
    this.parent,
    this.replyType,
    this.replyItem,
    this.heroTag,
  });

  @override
  State<VideoReplyNewDialog> createState() => _VideoReplyNewDialogState();
}

class _VideoReplyNewDialogState extends State<VideoReplyNewDialog>
    with WidgetsBindingObserver {
  final TextEditingController _replyContentController = TextEditingController();
  final FocusNode replyContentFocusNode = FocusNode();
  final GlobalKey _formKey = GlobalKey<FormState>();
  late double emoteHeight = 0.0;
  double keyboardHeight = 0.0; // 键盘高度
  final _debouncer = Debouncer(milliseconds: 200); // 设置延迟时间
  final _mentionDebouncer = Debouncer(milliseconds: 300);
  String toolbarType = 'input';
  RxBool isForward = false.obs;
  RxBool showForward = false.obs;
  RxString message = ''.obs;

  // ===== 图片评论 =====
  static const int maxImageCount = 9;
  final RxList<File> imageList = <File>[].obs;
  bool _isSending = false;

  // ===== @某人 =====
  // 输入 @ 后未完成的片段（用于联想与替换）
  String _mentionKeyword = '';
  final RxList<Map> _mentionResults = <Map>[].obs;
  final RxBool _mentionPanelVisible = false.obs;
  // 已插入的 @ 用户名 → mid 映射（随评论发送）
  final Map<String, int> _atNameToMid = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoFocus();
    _focuslistener();
    final String routePath = Get.currentRoute;
    if (routePath.startsWith('/video')) {
      showForward.value = true;
    }
  }

  _autoFocus() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (context.mounted) {
      FocusScope.of(context).requestFocus(replyContentFocusNode);
    }
  }

  _focuslistener() {
    replyContentFocusNode.addListener(() {
      if (replyContentFocusNode.hasFocus) {
        setState(() {
          toolbarType = 'input';
        });
      }
    });
  }

  // ===== 输入监听：检测 @ 联想 =====
  void _onTextChanged(String text) {
    message.value = text;
    _detectMention(text);
  }

  void _detectMention(String text) {
    final int cursor = _replyContentController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      _hideMentionPanel();
      return;
    }
    // 从光标向前找最近的 @（以空格/换行为终止）
    final String before = text.substring(0, cursor);
    final int atIndex = before.lastIndexOf('@');
    if (atIndex < 0) {
      _hideMentionPanel();
      return;
    }
    final String keyword = before.substring(atIndex + 1);
    if (keyword.contains(' ') ||
        keyword.contains('\n') ||
        keyword.length > 20) {
      _hideMentionPanel();
      return;
    }
    _mentionKeyword = keyword;
    _mentionDebouncer.run(() => _queryMention(keyword));
  }

  Future<void> _queryMention(String keyword) async {
    var res = await DynamicsHttp.dynMention(keyword: keyword);
    if (res['status'] == true) {
      final List items = res['data'] as List;
      _mentionResults
        ..clear()
        ..addAll(items.cast<Map>().take(10));
      _mentionPanelVisible.value = _mentionResults.isNotEmpty;
      setState(() {});
    }
  }

  void _hideMentionPanel() {
    _mentionPanelVisible.value = false;
    _mentionKeyword = '';
    _mentionResults.clear();
  }

  /// 选择联想用户：删除已输入的 @关键词，插入 @用户名+空格
  void _onChooseMention(Map user) {
    final String name = (user['name'] ?? '').toString();
    final int uid = int.tryParse('${user['uid']}') ?? 0;
    if (name.isEmpty) return;

    final String text = _replyContentController.text;
    final int cursor = _replyContentController.selection.baseOffset;
    final String before = text.substring(0, cursor);
    final String after = text.substring(cursor);
    final int atIndex = before.lastIndexOf('@');
    if (atIndex < 0) return;

    final String newText =
        before.substring(0, atIndex) + '@$name ' + after;
    final int newCursor = atIndex + name.length + 2;
    _replyContentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    message.value = newText;
    _atNameToMid[name] = uid;
    _hideMentionPanel();
    // 选择后回到输入框
    FocusScope.of(context).requestFocus(replyContentFocusNode);
  }

  // ===== 图片选择 =====
  Future<void> _pickImages() async {
    if (imageList.length >= maxImageCount) {
      SmartDialog.showToast('最多选择$maxImageCount张图片');
      return;
    }
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> picked = await picker.pickMultiImage(
        imageQuality: 100,
      );
      if (picked.isEmpty) return;
      final int remaining = maxImageCount - imageList.length;
      if (picked.length > remaining) {
        SmartDialog.showToast('最多选择$maxImageCount张图片，已截取前$remaining张');
      }
      imageList.addAll(
          picked.take(remaining).map((e) => File(e.path)).toList());
      setState(() {});
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  /// 视频截图：取当前播放帧加入图片列表
  Future<void> _screenshotVideo() async {
    if (imageList.length >= maxImageCount) {
      SmartDialog.showToast('最多选择$maxImageCount张图片');
      return;
    }
    try {
      final plc = PlPlayerController(videoType: 'none');
      final player = plc.videoPlayerController;
      if (player == null) {
        SmartDialog.showToast('播放器未就绪');
        return;
      }
      final Uint8List? shot = await player.screenshot(format: 'image/png');
      if (shot == null) {
        SmartDialog.showToast('截图失败');
        return;
      }
      final Directory tmp = Directory.systemTemp;
      final String path =
          '${tmp.path}/reply_shot_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(shot);
      imageList.add(File(path));
      setState(() {});
      SmartDialog.showToast('已添加视频截图');
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  // ===== 视频进度插入 =====
  void _insertVideoProgress() {
    try {
      final plc = PlPlayerController(videoType: 'none');
      final Duration pos = plc.position.value;
      final int seconds = pos.inSeconds;
      final int h = seconds ~/ 3600;
      final int m = (seconds % 3600) ~/ 60;
      final int s = seconds % 60;
      final String mm = m.toString().padLeft(2, '0');
      final String ss = s.toString().padLeft(2, '0');
      final String stamp = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
      _insertText(' $stamp ');
      SmartDialog.showToast('已插入 $stamp');
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  /// 在光标处插入文本
  void _insertText(String insert) {
    final int cursor =
        _replyContentController.selection.baseOffset < 0 ? _replyContentController.text.length : _replyContentController.selection.baseOffset;
    final String text = _replyContentController.text;
    final String newText =
        text.substring(0, cursor) + insert + text.substring(cursor);
    _replyContentController.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: cursor + insert.length),
    );
    message.value = newText;
  }

  // ===== 发送 =====
  Future submitReplyAdd() async {
    feedBack();
    if (_isSending) return;
    _isSending = true;
    try {
      // 先上传图片（biz=new_dyn, category=daily）
      List<Map<String, dynamic>>? pictures;
      if (imageList.isNotEmpty) {
        SmartDialog.showLoading(msg: '正在上传图片 0/${imageList.length}');
        pictures = [];
        for (int i = 0; i < imageList.length; i++) {
          final File img = imageList[i];
          final upRes = await MsgHttp.uploadBfs(
            path: img.path,
            biz: 'new_dyn',
            category: 'daily',
          );
          if (upRes['status'] != true) {
            SmartDialog.dismiss();
            SmartDialog.showToast('第${i + 1}张图片上传失败：${upRes['msg']}');
            _isSending = false;
            return;
          }
          final data = upRes['data'];
          pictures.add({
            'img_width':
                (num.tryParse('${data['image_width']}') ?? 1).toInt(),
            'img_height':
                (num.tryParse('${data['image_height']}') ?? 1).toInt(),
            'img_size': (num.tryParse('${data['img_size']}') ?? 0).toInt(),
            'img_src': data['image_url'],
          });
          SmartDialog.showLoading(
              msg: '正在上传图片 ${i + 1}/${imageList.length}');
        }
        SmartDialog.dismiss();
      }

      final String msgText = widget.replyItem != null &&
              widget.replyItem!.root != 0
          ? ' 回复 @${widget.replyItem!.member!.uname!} : ${message.value}'
          : message.value;
      var result = await VideoHttp.replyAdd(
        type: widget.replyType ?? ReplyType.video,
        oid: widget.oid!,
        root: widget.root!,
        parent: widget.parent!,
        message: msgText,
        pictures: pictures,
        atNameToMid: _atNameToMid.isNotEmpty ? _atNameToMid : null,
      );
      if (result['status']) {
        SmartDialog.showToast(result['data']['success_toast']);
        Get.back(result: {
          'data': ReplyItemModel.fromJson(result['data']['reply'], ''),
        });

        /// 投稿、番剧页面
        if (isForward.value) {
          await DynamicsHttp.dynamicCreate(
            mid: 0,
            rawText: message.value,
            oid: widget.oid!,
            scene: 5,
          );
        }
      } else {
        SmartDialog.showToast(result['msg']);
      }
    } finally {
      _isSending = false;
    }
  }

  void onChooseEmote(PackageItem package, Emote emote) {
    final int cursorPosition = _replyContentController.selection.baseOffset;
    final String currentText = _replyContentController.text;
    final String newText = currentText.substring(0, cursorPosition) +
        emote.text! +
        currentText.substring(cursorPosition);
    message.value = newText;
    _replyContentController.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: cursorPosition + emote.text!.length),
    );
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final String routePath = Get.currentRoute;
    if (mounted &&
        (routePath.startsWith('/video') ||
            routePath.startsWith('/dynamicDetail'))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 键盘高度
        final viewInsets = EdgeInsets.fromViewPadding(
            View.of(context).viewInsets, View.of(context).devicePixelRatio);
        _debouncer.run(() {
          if (mounted) {
            if (keyboardHeight == 0 && emoteHeight == 0) {
              setState(() {
                emoteHeight = keyboardHeight =
                    keyboardHeight == 0.0 ? viewInsets.bottom : keyboardHeight;
              });
            }
          }
        });
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _replyContentController.dispose();
    replyContentFocusNode.removeListener(() {});
    replyContentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double _keyboardHeight = EdgeInsets.fromViewPadding(
            View.of(context).viewInsets, View.of(context).devicePixelRatio)
        .bottom;
    final bool isVideoPage = Get.currentRoute.startsWith('/video');
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(
              maxHeight: 200,
              minHeight: 110,
            ),
            padding: const EdgeInsets.only(top: 12, right: 12, left: 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: TextField(
                        controller: _replyContentController,
                        minLines: 3,
                        maxLines: null,
                        autofocus: false,
                        focusNode: replyContentFocusNode,
                        decoration: const InputDecoration(
                            hintText: "输入回复内容",
                            border: InputBorder.none,
                            hintStyle: TextStyle(
                              fontSize: 14,
                            )),
                        style: Theme.of(context).textTheme.bodyLarge,
                        onChanged: _onTextChanged,
                      ),
                    ),
                  ),
                ),
                // 发送键：输入框最右侧，垂直对齐输入框中部
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    height: 36,
                    child: Obx(
                      () => FilledButton(
                        onPressed: (message.isNotEmpty || imageList.isNotEmpty)
                            ? submitReplyAdd
                            : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('发送'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 已选图片缩略图列表
          Obx(() {
            if (imageList.isEmpty) return const SizedBox.shrink();
            return Container(
              height: 100,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imageList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          imageList[index],
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: -6,
                        top: -6,
                        child: GestureDetector(
                          onTap: () {
                            imageList.removeAt(index);
                            setState(() {});
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .inverseSurface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color:
                                  Theme.of(context).colorScheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          }),
          Divider(
            height: 1,
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
          Container(
            height: 52,
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
            ),
            margin: EdgeInsets.only(
              bottom: toolbarType == 'input' && keyboardHeight == 0.0
                  ? MediaQuery.of(context).padding.bottom
                  : 0,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                        ToolbarIconButton(
                          onPressed: () {
                            if (toolbarType == 'emote') {
                              setState(() {
                                toolbarType = 'input';
                              });
                            }
                            FocusScope.of(context)
                                .requestFocus(replyContentFocusNode);
                          },
                          icon: const Icon(Icons.keyboard, size: 22),
                          toolbarType: toolbarType,
                          selected: toolbarType == 'input',
                        ),
                        const SizedBox(width: 12),
                        ToolbarIconButton(
                          onPressed: () {
                            if (toolbarType == 'input') {
                              setState(() {
                                toolbarType = 'emote';
                              });
                            }
                            FocusScope.of(context).unfocus();
                            _hideMentionPanel();
                          },
                          icon: const Icon(Icons.emoji_emotions, size: 22),
                          toolbarType: toolbarType,
                          selected: toolbarType == 'emote',
                        ),
                        const SizedBox(width: 12),
                        // @某人
                        ToolbarIconButton(
                          onPressed: () {
                            _insertText('@');
                            FocusScope.of(context)
                                .requestFocus(replyContentFocusNode);
                          },
                          icon: const Icon(Icons.alternate_email, size: 22),
                          toolbarType: toolbarType,
                          selected: false,
                        ),
                        const SizedBox(width: 12),
                        // 图片
                        ToolbarIconButton(
                          onPressed: _pickImages,
                          icon: const Icon(Icons.image_outlined, size: 22),
                          toolbarType: toolbarType,
                          selected: false,
                        ),
                        // 视频页专属：截图 + 进度 + 笔记
                        if (isVideoPage) ...[
                          const SizedBox(width: 12),
                          ToolbarIconButton(
                            onPressed: _screenshotVideo,
                            icon: const Icon(
                                Icons.enhance_photo_translate_outlined,
                                size: 22),
                            toolbarType: toolbarType,
                            selected: false,
                          ),
                          const SizedBox(width: 12),
                          ToolbarIconButton(
                            onPressed: _insertVideoProgress,
                            icon: const Icon(Icons.my_location, size: 22),
                            toolbarType: toolbarType,
                            selected: false,
                          ),
                          const SizedBox(width: 12),
                          ToolbarIconButton(
                            onPressed: () => Get.toNamed(
                              '/noteCreate',
                              parameters: {
                                'oid': widget.oid.toString(),
                                'replyType':
                                    (widget.replyType ?? ReplyType.video).index
                                        .toString(),
                              },
                            ),
                            icon: const Icon(Icons.edit_note, size: 22),
                            toolbarType: toolbarType,
                            selected: false,
                          ),
                        ],
                        const SizedBox(width: 12),
                        Obx(
                          () => showForward.value
                              ? TextButton.icon(
                                  onPressed: () {
                                    isForward.value = !isForward.value;
                                  },
                                  icon: Icon(
                                      isForward.value
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      size: 22),
                                  label: const Text('转发到动态'),
                                  style: ButtonStyle(
                                    padding: MaterialStateProperty.all(
                                        EdgeInsets.zero),
                                    foregroundColor:
                                        MaterialStateProperty.all(
                                      isForward.value
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .outline,
                                    ),
                                  ),
                                )
                              : const SizedBox(),
                  ),
                ],
              ),
            ),
          ),
          // @联想面板（在键盘/表情区上方叠加）
          Obx(() {
            if (!_mentionPanelVisible.value) return const SizedBox.shrink();
            return Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: MentionPanel(
                results: _mentionResults.toList(),
                onChoose: _onChooseMention,
                keyword: _mentionKeyword,
              ),
            );
          }),
          AnimatedSize(
            curve: Curves.easeInOut,
            duration: const Duration(milliseconds: 300),
            child: SizedBox(
              width: double.infinity,
              height: toolbarType == 'input'
                  ? (_keyboardHeight > keyboardHeight
                      ? _keyboardHeight
                      : keyboardHeight)
                  : emoteHeight,
              child: EmotePanel(
                onChoose: (package, emote) => onChooseEmote(package, emote),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef DebounceCallback = void Function();

class Debouncer {
  DebounceCallback? callback;
  final int? milliseconds;
  Timer? _timer;

  Debouncer({this.milliseconds});

  run(DebounceCallback callback) {
    if (_timer != null) {
      _timer!.cancel();
    }
    _timer = Timer(Duration(milliseconds: milliseconds!), () {
      callback();
    });
  }
}
