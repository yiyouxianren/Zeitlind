import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/http_error.dart';
import 'package:pilipala/common/skeleton/video_card_h.dart';
import 'package:pilipala/pages/fav/controller.dart';
import 'package:pilipala/pages/fav/widgets/item.dart';

/// 极简模式首页：收藏夹列表（默认收藏夹 + 自建收藏夹），
/// 点进任意收藏夹即可查看收藏内容
class SimpleFavPage extends StatefulWidget {
  const SimpleFavPage({super.key});

  @override
  State<SimpleFavPage> createState() => _SimpleFavPageState();
}

class _SimpleFavPageState extends State<SimpleFavPage>
    with AutomaticKeepAliveClientMixin {
  final FavController _favController = Get.put(FavController());
  late Future _futureBuilderFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _futureBuilderFuture = _favController.queryFavFolder();
    _favController.scrollController.addListener(() {
      final sc = _favController.scrollController;
      if (sc.position.pixels >= sc.position.maxScrollExtent - 300) {
        _favController.onLoad();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () async {
        _favController.hasMore.value = true;
        _favController.currentPage = 1;
        setState(() {
          _futureBuilderFuture = _favController.queryFavFolder(type: 'init');
        });
      },
      child: FutureBuilder(
        future: _futureBuilderFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            Map? data = snapshot.data;
            if (data != null && data['status']) {
              return Obx(
                () => ListView.builder(
                  controller: _favController.scrollController,
                  itemCount: _favController.favFolderList.length,
                  itemBuilder: (context, index) {
                    return FavItem(
                      favFolderItem: _favController.favFolderList[index],
                      isOwner: _favController.isOwner.value,
                    );
                  },
                ),
              );
            } else {
              return ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 1,
                itemBuilder: (context, index) => HttpError(
                  errMsg: data?['msg'] ?? '请求异常',
                  fn: () {
                    setState(() {
                      _futureBuilderFuture = _favController.queryFavFolder();
                    });
                  },
                ),
              );
            }
          } else {
            return ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 10,
              itemBuilder: (context, index) =>
                  const VideoCardHSkeleton(),
            );
          }
        },
      ),
    );
  }
}
