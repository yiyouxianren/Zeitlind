class LiveFollowingModel {
  int? count;
  List<LiveFollowingItemModel> list = <LiveFollowingItemModel>[];
  int? liveCount;
  int? neverLivedCount;
  List? neverLivedFaces;
  int? pageSize;
  String? title;
  int? totalPage;

  LiveFollowingModel({
    this.count,
    List<LiveFollowingItemModel>? list,
    this.liveCount,
    this.neverLivedCount,
    this.neverLivedFaces,
    this.pageSize,
    this.title,
    this.totalPage,
  }) : list = list ?? <LiveFollowingItemModel>[];

  LiveFollowingModel.fromJson(Map<String, dynamic> json) {
    count = json['count'];
    final rawList = json['list'];
    if (rawList is List) {
      list = rawList
          .whereType<Map>()
          .map((item) => LiveFollowingItemModel.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    }
    liveCount = json['live_count'];
    neverLivedCount = json['never_lived_count'];
    if (json['never_lived_faces'] != null) {
      neverLivedFaces = <dynamic>[];
      json['never_lived_faces'].forEach((v) {
        neverLivedFaces!.add(v);
      });
    }
    pageSize = json['pageSize'];
    title = json['title'];
    totalPage = json['totalPage'];
  }
}

class LiveFollowingItemModel {
  int? roomId;
  int? uid;
  String? uname;
  String? title;
  String? face;
  int? liveStatus;
  int? recordNum;
  String? recentRecordId;
  int? isAttention;
  int? clipNum;
  int? fansNum;
  String? areaName;
  String? areaValue;
  String? tags;
  String? recentRecordIdV2;
  int? recordNumV2;
  int? recordLiveTime;
  String? areaNameV2;
  String? roomNews;
  String? watchIcon;
  String? textSmall;
  String? roomCover;
  String? pic;
  int? parentAreaId;
  int? areaId;

  LiveFollowingItemModel({
    this.roomId,
    this.uid,
    this.uname,
    this.title,
    this.face,
    this.liveStatus,
    this.recordNum,
    this.recentRecordId,
    this.isAttention,
    this.clipNum,
    this.fansNum,
    this.areaName,
    this.areaValue,
    this.tags,
    this.recentRecordIdV2,
    this.recordNumV2,
    this.recordLiveTime,
    this.areaNameV2,
    this.roomNews,
    this.watchIcon,
    this.textSmall,
    this.roomCover,
    this.pic,
    this.parentAreaId,
    this.areaId,
  });

  LiveFollowingItemModel.fromJson(Map<String, dynamic> json) {
    roomId = _asInt(json['roomid'] ?? json['room_id']);
    uid = _asInt(json['uid']);
    uname = (json['uname'] ?? json['nickname'])?.toString();
    title = (json['title'] ?? json['roomname'])?.toString();
    face = json['face']?.toString();
    liveStatus = _asInt(json['live_status']) ?? 1;
    recordNum = json['record_num'];
    recentRecordId = json['recent_record_id'];
    isAttention = json['is_attention'];
    clipNum = json['clipnum'];
    fansNum = json['fans_num'];
    areaName = (json['area_name'] ?? json['area_v2_name'])?.toString();
    areaValue = json['area_value']?.toString();
    tags = json['tags']?.toString();
    recentRecordIdV2 = json['recent_record_id_v2'];
    recordNumV2 = json['record_num_v2'];
    recordLiveTime = _asInt(json['record_live_time']) ?? 0;
    areaNameV2 = (json['area_name_v2'] ?? json['area_v2_name'])?.toString();
    roomNews = json['room_news']?.toString();
    watchIcon = json['watch_icon']?.toString();
    textSmall = json['text_small']?.toString();
    roomCover =
        (json['room_cover'] ?? json['cover_from_user'] ?? json['keyframe'])
            ?.toString();
    pic = roomCover;
    parentAreaId = _asInt(json['parent_area_id'] ?? json['area_v2_parent_id']);
    areaId = _asInt(json['area_id'] ?? json['area_v2_id']);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
