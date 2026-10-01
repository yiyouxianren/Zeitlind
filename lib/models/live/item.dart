class LiveItemModel {
  LiveItemModel({
    this.roomId,
    this.uid,
    this.title,
    this.uname,
    this.online,
    this.userCover,
    this.userCoverFlag,
    this.systemCover,
    this.cover,
    this.pic,
    this.link,
    this.face,
    this.parentId,
    this.parentName,
    this.areaId,
    this.areaName,
    this.sessionId,
    this.groupId,
    this.pkId,
    this.verify,
    this.headBox,
    this.headBoxType,
    this.watchedShow,
  });

  int? roomId;
  int? uid;
  String? title;
  String? uname;
  int? online;
  String? userCover;
  int? userCoverFlag;
  String? systemCover;
  String? cover;
  String? pic;
  String? link;
  String? face;
  int? parentId;
  String? parentName;
  int? areaId;
  String? areaName;
  String? sessionId;
  int? groupId;
  int? pkId;
  Map? verify;
  Map? headBox;
  int? headBoxType;
  Map? watchedShow;

  LiveItemModel.fromJson(Map<String, dynamic> json) {
    roomId = _asInt(json['roomid'] ?? json['room_id']);
    uid = _asInt(json['uid']);
    title = json['title']?.toString();
    uname = (json['uname'] ?? json['nickname'])?.toString();
    online = _asInt(json['online']);
    userCover = json['user_cover']?.toString();
    userCoverFlag = _asInt(json['user_cover_flag']);
    systemCover = json['system_cover']?.toString();
    cover = (json['cover'] ?? json['keyframe'] ?? json['cover_from_user'])
        ?.toString();
    pic = cover;
    link = json['link']?.toString();
    face = json['face']?.toString();
    parentId = _asInt(json['parent_id'] ?? json['area_v2_parent_id']);
    parentName =
        (json['parent_name'] ?? json['area_v2_parent_name'])?.toString();
    areaId = _asInt(json['area_id'] ?? json['area_v2_id']);
    areaName = (json['area_name'] ?? json['area_v2_name'])?.toString();
    sessionId = json['session_id']?.toString();
    groupId = _asInt(json['group_id']);
    pkId = _asInt(json['pk_id']);
    verify = json['verify'];
    headBox = json['head_box'];
    headBoxType = _asInt(json['head_box_type']);
    watchedShow = json['watched_show'];
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
