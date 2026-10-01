import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pilipala/http/msg.dart';
import 'package:pilipala/http/note.dart';

/// 笔记编辑页：标题 + 正文 + 多图，发布为笔记（图文评论）
class NoteCreatePage extends StatefulWidget {
  const NoteCreatePage({super.key});

  @override
  State<NoteCreatePage> createState() => _NoteCreatePageState();
}

class _NoteCreatePageState extends State<NoteCreatePage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final RxList<File> _imageList = <File>[].obs;
  static const int maxImageCount = 9;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    final Map<String, String?> params = Get.parameters;
    debugPrint('NoteCreate: params=$params');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_imageList.length >= maxImageCount) {
      SmartDialog.showToast('最多选择$maxImageCount张图片');
      return;
    }
    try {
      final List<XFile> picked = await ImagePicker().pickMultiImage(
        imageQuality: 100,
      );
      if (picked.isEmpty) return;
      final int remaining = maxImageCount - _imageList.length;
      if (picked.length > remaining) {
        SmartDialog.showToast('最多$maxImageCount张，已截取前$remaining张');
      }
      _imageList.addAll(
          picked.take(remaining).map((e) => File(e.path)).toList());
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  Future<void> _publish() async {
    if (_isPublishing) return;
    final String title = _titleController.text.trim();
    final String content = _contentController.text.trim();
    if (title.isEmpty) {
      SmartDialog.showToast('请输入标题');
      return;
    }
    if (content.isEmpty) {
      SmartDialog.showToast('请输入正文');
      return;
    }
    _isPublishing = true;
    try {
      // 上传图片
      List<Map<String, dynamic>> banners = [];
      if (_imageList.isNotEmpty) {
        for (int i = 0; i < _imageList.length; i++) {
          SmartDialog.showLoading(msg: '正在上传图片 ${i + 1}/${_imageList.length}');
          final upRes = await MsgHttp.uploadBfs(
            path: _imageList[i].path,
            biz: 'new_dyn',
            category: 'daily',
          );
          if (upRes['status'] != true) {
            SmartDialog.dismiss();
            SmartDialog.showToast('第${i + 1}张图片上传失败：${upRes['msg']}');
            _isPublishing = false;
            return;
          }
          final data = upRes['data'];
          banners.add({
            'img_width':
                (num.tryParse('${data['image_width']}') ?? 1).toInt(),
            'img_height':
                (num.tryParse('${data['image_height']}') ?? 1).toInt(),
            'img_size': (num.tryParse('${data['img_size']}') ?? 0).toInt(),
            'img_src': data['image_url'],
          });
        }
        SmartDialog.dismiss();
      }

      final Map<String, String?> params = Get.parameters;
      final int? oid = int.tryParse(params['oid'] ?? '');
      final int? replyType = int.tryParse(params['replyType'] ?? '');

      SmartDialog.showLoading(msg: '正在发布');
      final result = await NoteHttp.addNote(
        title: title,
        summary: content,
        banners: banners,
        oid: oid,
        replyType: replyType,
      );
      SmartDialog.dismiss();
      if (result['status'] == true) {
        SmartDialog.showToast('笔记发布成功，审核通过后将展示在评论区');
        Get.back();
      } else {
        SmartDialog.showToast(result['msg'] ?? '发布失败');
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
    } finally {
      _isPublishing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text('发布笔记', style: Theme.of(context).textTheme.titleMedium),
        actions: [
          TextButton(
            onPressed: _publish,
            child: const Text('发布'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              maxLength: 40,
              decoration: const InputDecoration(
                hintText: '输入笔记标题',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const Divider(height: 1),
            TextField(
              controller: _contentController,
              maxLines: 8,
              minLines: 5,
              decoration: const InputDecoration(
                hintText: '输入笔记正文',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 8),
            Obx(() => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < _imageList.length; i++)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              _imageList[i],
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: GestureDetector(
                              onTap: () => _imageList.removeAt(i),
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_imageList.length < maxImageCount)
                      GestureDetector(
                        onTap: _pickImages,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withOpacity(0.4),
                            ),
                          ),
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 32,
                            color:
                                Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                )),
            const SizedBox(height: 16),
            Text(
              '笔记将以图文形式发布，审核通过后展示在视频评论区',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
