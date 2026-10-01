import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/models/read/opus.dart';
import 'package:pilipala/pages/video/detail/reply/widgets/reply_item.dart';
import 'package:pilipala/models/common/reply_type.dart';
import 'controller.dart';
import 'text_helper.dart';

class OpusPage extends StatefulWidget {
  const OpusPage({super.key});

  @override
  State<OpusPage> createState() => _OpusPageState();
}

class _OpusPageState extends State<OpusPage> {
  final OpusController controller = Get.put(OpusController());
  late Future _futureBuilderFuture;

  @override
  void initState() {
    super.initState();
    _futureBuilderFuture = controller.fetchOpusData();
    controller.scrollController.addListener(controller.onScroll);
  }

  @override
  void dispose() {
    controller.scrollController.removeListener(controller.onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Obx(
        () => CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitle(),
                  _buildFutureContent(),
                ],
              ),
            ),
            SliverToBoxAdapter(child: _buildCommentsHeader()),
            if (controller.replies.isEmpty && controller.commentsLoading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => const SizedBox(height: 70),
                  childCount: 3,
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == controller.replies.length) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(controller.commentsLoading
                              ? '加载中...'
                              : controller.replyMessage),
                        ),
                      );
                    }
                    final reply = controller.replies[index];
                    final typeIndex = controller.commentType >= 0 &&
                            controller.commentType < ReplyType.values.length
                        ? controller.commentType
                        : ReplyType.column.index;
                    return ReplyItem(
                      replyItem: reply,
                      replyType: ReplyType.values[typeIndex],
                      replyReply: (_, __, ___) {},
                    );
                  },
                  childCount: controller.replies.length + 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: StreamBuilder(
        stream: controller.appbarStream.stream.distinct(),
        initialData: false,
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          return AnimatedOpacity(
            opacity: snapshot.data ? 1 : 0,
            curve: Curves.easeOut,
            duration: const Duration(milliseconds: 500),
            child: Obx(
              () => Text(
                controller.title.value,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          );
        },
      ),
      actions: [
        PopupMenuButton(
          icon: const Icon(Icons.more_vert_outlined),
          itemBuilder: (BuildContext context) => <PopupMenuEntry>[
            PopupMenuItem(
              onTap: controller.onJumpWebview,
              child: const Text('查看原网页'),
            )
          ],
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildCommentsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        '评论 ${controller.replies.length}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Obx(
        () => Text(
          controller.title.value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildFutureContent() {
    return FutureBuilder(
      future: _futureBuilderFuture,
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.data == null) {
            return const SizedBox();
          }
          if (snapshot.data['status']) {
            return _buildContent(controller.opusData.value);
          } else {
            return _buildError(
                snapshot.data['msg'] ?? snapshot.data['message'] ?? '专栏加载失败');
          }
        } else {
          return _buildLoading();
        }
      },
    );
  }

  Widget _buildContent(OpusDataModel opusData) {
    if (opusData.detail == null || opusData.detail!.modules == null) {
      return _buildError('专栏正文为空');
    }
    final modules = opusData.detail!.modules!;
    final moduleIndex =
        modules.indexWhere((module) => module.moduleContent != null);
    if (moduleIndex < 0 ||
        modules[moduleIndex].moduleContent?.paragraphs == null) {
      return _buildError('专栏正文暂不可解析');
    }
    final moduleContent = modules[moduleIndex].moduleContent!;

    final List<String> picList = [];
    for (final paragraph in moduleContent.paragraphs ?? <ModuleParagraph>[]) {
      for (final pic in paragraph.pic?.pics ?? <Pic>[]) {
        if (pic.url != null) picList.add(pic.url!);
      }
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).padding.bottom + 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: _buildStatsWidget(opusData),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _buildAuthorWidget(opusData),
          ),
          ...moduleContent.paragraphs!.map(
            (ModuleParagraph paragraph) {
              return Column(
                children: [
                  if (paragraph.paraType == 1) ...[
                    Container(
                      width: double.infinity,
                      alignment: TextHelper.getAlignment(paragraph.align),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: SelectableText.rich(
                        TextSpan(
                          children: paragraph.text?.nodes?.map((node) {
                                return TextHelper.buildTextSpan(
                                    node, paragraph.align, context);
                              }).toList() ??
                              [],
                        ),
                      ),
                    )
                  ] else if (paragraph.paraType == 2) ...[
                    ...paragraph.pic?.pics?.map(
                          (Pic pic) => Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(top: 10, bottom: 10),
                              child: InkWell(
                                onTap: () {
                                  controller.onPreviewImg(
                                    picList,
                                    picList.indexOf(pic.url!),
                                    context,
                                  );
                                },
                                child: Builder(
                                  builder: (context) {
                                    final scale = pic.scale ?? 1.0;
                                    final aspectRatio = pic.aspectRatio ?? 1.0;
                                    return NetworkImgLayer(
                                      src: pic.url,
                                      width: (Get.width - 32) * scale,
                                      height: (Get.width - 32) *
                                          scale /
                                          aspectRatio,
                                      type: 'emote',
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ) ??
                        [],
                  ] else
                    const SizedBox(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorWidget(OpusDataModel opusData) {
    final modules = opusData.detail!.modules!;
    late ModuleAuthor moduleAuthor;
    final int moduleIndex =
        modules.indexWhere((module) => module.moduleAuthor != null);
    if (moduleIndex != -1) {
      moduleAuthor = modules[moduleIndex].moduleAuthor!;
    } else {
      return const SizedBox();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NetworkImgLayer(
          width: 48,
          height: 48,
          type: 'avatar',
          src: moduleAuthor.face,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                moduleAuthor.name ?? '未知用户',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              StyledText(moduleAuthor.pubTime ?? ''),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsWidget(OpusDataModel opusData) {
    final modules = opusData.detail!.modules!;
    ModuleStat? moduleStat;
    for (final module in modules) {
      if (module.moduleStat != null) {
        moduleStat = module.moduleStat;
        break;
      }
    }
    if (moduleStat == null) return const SizedBox();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        if (moduleStat.comment != null)
          StyledText('${moduleStat.comment!.count ?? 0}评论'),
        if (moduleStat.like != null)
          StyledText('${moduleStat.like!.count ?? 0}赞'),
        if (moduleStat.favorite != null)
          StyledText('${moduleStat.favorite!.count ?? 0}转发'),
      ],
    );
  }

  Widget _buildError(String message) {
    return SizedBox(
      height: 100,
      child: Center(
        child: Text(message),
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 100,
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class StyledText extends StatelessWidget {
  final String text;

  const StyledText(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
