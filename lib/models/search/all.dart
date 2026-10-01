import 'result.dart';

class SearchAllModel {
  SearchAllModel({this.topTList, this.users, this.videos});

  Map? topTList;

  /// 综合搜索中置顶的 UP 主列表（bili_user block）
  List<SearchUserItemModel>? users;

  /// 综合搜索中的视频列表（video block，仅综合模式填充）
  List<SearchVideoItemModel>? videos;

  SearchAllModel.fromJson(Map<String, dynamic> json) {
    topTList = json['top_tlist'];
    final List? result = json['result'];
    if (result is List) {
      final List<SearchUserItemModel> userList = [];
      final List<SearchVideoItemModel> videoList = [];
      for (final block in result) {
        if (block is! Map) continue;
        final String type = block['result_type']?.toString() ?? '';
        final List? data = block['data'];
        if (data is! List) continue;
        if (type == 'bili_user') {
          for (final item in data) {
            if (item is Map) {
              userList.add(SearchUserItemModel
                  .fromJson(Map<String, dynamic>.from(item)));
            }
          }
        } else if (type == 'video') {
          for (final item in data) {
            if (item is Map) {
              videoList.add(SearchVideoItemModel
                  .fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
      }
      users = userList;
      videos = videoList;
    }
  }
}
