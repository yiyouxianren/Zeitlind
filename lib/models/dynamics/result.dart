import 'dart:convert';

class DynamicsDataModel {
  DynamicsDataModel({
    this.hasMore,
    this.items,
    this.offset,
  });
  bool? hasMore;
  bool? loadNext;
  List<DynamicItemModel>? items;
  String? offset;

  DynamicsDataModel.fromJson(Map<String, dynamic> json) {
    hasMore = _asBool(json['has_more']);
    loadNext = _asBool(json['load_next']);
    final rawItems = json['items'];
    items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) {
              try {
                return DynamicItemModel.fromJson(
                    Map<String, dynamic>.from(item));
              } catch (_) {
                return null;
              }
            })
            .whereType<DynamicItemModel>()
            .toList()
        : <DynamicItemModel>[];
    offset = json['offset']?.toString().trim() ?? '';
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }
}

// 单个动态
class DynamicItemModel {
  DynamicItemModel({
    this.basic,
    this.idStr,
    this.modules,
    this.orig,
    this.type,
    this.visible,
  });

  Map? basic;
  String? idStr;
  ItemModulesModel? modules;
  ItemOrigModel? orig;
  String? type;
  bool? visible;

  DynamicItemModel.fromJson(Map<String, dynamic> json) {
    basic = json['basic'];
    idStr = json['id_str'];
    modules = json['modules'] is Map
        ? ItemModulesModel.fromJson(
            Map<String, dynamic>.from(json['modules'] as Map))
        : null;
    orig = json['orig'] != null ? ItemOrigModel.fromJson(json['orig']) : null;
    type = json['type'];
    visible = json['visible'];
  }
}

class ItemOrigModel {
  ItemOrigModel({
    this.basic,
    this.isStr,
    this.modules,
    this.type,
    this.visible,
  });

  Map? basic;
  String? isStr;
  ItemModulesModel? modules;
  String? type;
  bool? visible;

  ItemOrigModel.fromJson(Map<String, dynamic> json) {
    basic = json['basic'];
    isStr = json['is_str'];
    modules = json['modules'] is Map
        ? ItemModulesModel.fromJson(
            Map<String, dynamic>.from(json['modules'] as Map))
        : null;
    type = json['type'];
    visible = json['visible'];
  }
}

// 单个动态详情
class ItemModulesModel {
  ItemModulesModel({
    this.moduleAuthor,
    this.moduleDynamic,
    // this.moduleInter,
    this.moduleStat,
    this.moduleTag,
  });

  ModuleAuthorModel? moduleAuthor;
  ModuleDynamicModel? moduleDynamic;
  // ModuleInterModel? moduleInter;
  ModuleStatModel? moduleStat;
  Map? moduleTag;

  ItemModulesModel.fromJson(Map<String, dynamic> json) {
    moduleAuthor = json['module_author'] != null
        ? ModuleAuthorModel.fromJson(json['module_author'])
        : null;
    moduleDynamic = json['module_dynamic'] != null
        ? ModuleDynamicModel.fromJson(json['module_dynamic'])
        : null;
    // moduleInter = ModuleInterModel.fromJson(json['module_interaction']);
    moduleStat = json['module_stat'] != null
        ? ModuleStatModel.fromJson(json['module_stat'])
        : null;
    moduleTag = json['module_tag'];
  }
}

// 单个动态详情 - 作者信息
class ModuleAuthorModel {
  ModuleAuthorModel({
    // this.avatar,
    // this.decorate,
    this.face,
    this.following,
    this.jumpUrl,
    this.label,
    this.mid,
    this.name,
    // this.officialVerify,
    // this.pandant,
    this.pubAction,
    // this.pubLocationText,
    this.pubTime,
    this.pubTs,
    this.type,
    this.vip,
  });

  String? face;
  bool? following;
  String? jumpUrl;
  String? label;
  int? mid;
  String? name;
  String? pubAction;
  String? pubTime;
  int? pubTs;
  String? type;
  Map? vip;

  ModuleAuthorModel.fromJson(Map<String, dynamic> json) {
    face = json['face'];
    following = json['following'];
    jumpUrl = json['jump_url'];
    label = json['label'];
    mid = _asInt(json['mid']);
    name = json['name'];
    pubAction = json['pub_action'];
    pubTime = json['pub_time'];
    pubTs = _asInt(json['pub_ts']);
    type = json['type'];
    vip = json['vip'];
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value == 0 ? null : value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed == 0 ? null : parsed;
  }
}

// 单个动态详情 - 动态信息
class ModuleDynamicModel {
  ModuleDynamicModel({
    this.additional,
    this.desc,
    this.major,
    this.topic,
  });

  DynamicAddModel? additional;
  DynamicDescModel? desc;
  DynamicMajorModel? major;
  DynamicTopicModel? topic;

  ModuleDynamicModel.fromJson(Map<String, dynamic> json) {
    additional = json['additional'] != null
        ? DynamicAddModel.fromJson(json['additional'])
        : null;
    desc =
        json['desc'] != null ? DynamicDescModel.fromJson(json['desc']) : null;
    if (json['major'] != null) {
      major = DynamicMajorModel.fromJson(json['major']);
    }
    topic = json['topic'] != null
        ? DynamicTopicModel.fromJson(json['topic'])
        : null;
  }
}

// 单个动态详情 - 评论？信息
// class ModuleInterModel {
//   ModuleInterModel({

//   });

//   ModuleInterModel.fromJson(Map<String, dynamic> json) {

//   }
// }
class DynamicAddModel {
  DynamicAddModel({
    this.type,
    this.vote,
    this.ugc,
    this.reserve,
    this.goods,
  });

  String? type;
  Vote? vote;
  Ugc? ugc;
  Reserve? reserve;
  Good? goods;

  /// TODO 比赛vs
  String? match;

  /// TODO 游戏信息
  String? common;

  DynamicAddModel.fromJson(Map<String, dynamic> json) {
    type = json['type'];
    vote = json['vote'] != null ? Vote.fromJson(json['vote']) : null;
    ugc = json['ugc'] != null ? Ugc.fromJson(json['ugc']) : null;
    reserve =
        json['reserve'] != null ? Reserve.fromJson(json['reserve']) : null;
    goods = json['goods'] != null ? Good.fromJson(json['goods']) : null;
  }
}

class Vote {
  Vote({
    this.choiceCnt,
    this.defaultShare,
    this.share,
    this.endTime,
    this.joinNum,
    this.status,
    this.type,
    this.uid,
    this.voteId,
  });

  int? choiceCnt;
  String? share;
  int? defaultShare;
  int? endTime;
  int? joinNum;
  int? status;
  int? type;
  int? uid;
  int? voteId;

  Vote.fromJson(Map<String, dynamic> json) {
    choiceCnt = json['choice_cnt'];
    share = json['share'];
    defaultShare = json['default_share'];
    endTime = json['end_time'] is int
        ? json['end_time']
        : int.parse(json['end_time']);
    joinNum = json['join_num'];
    status = json['status'];
    type = json['type'];
    uid = json['uid'];
    voteId = json['vote_id'];
  }
}

class Ugc {
  Ugc({
    this.cover,
    this.descSecond,
    this.duration,
    this.headText,
    this.idStr,
    this.jumpUrl,
    this.multiLine,
    this.title,
  });

  String? cover;
  String? descSecond;
  String? duration;
  String? headText;
  String? idStr;
  String? jumpUrl;
  bool? multiLine;
  String? title;

  Ugc.fromJson(Map<String, dynamic> json) {
    cover = json['cover'];
    descSecond = json['desc_second'];
    duration = json['duration'];
    headText = json['head_text'];
    idStr = json['id_str'];
    jumpUrl = json['jump_url'];
    multiLine = json['multi_line'];
    title = json['title'];
  }
}

class Reserve {
  Reserve({
    this.button,
    this.desc1,
    this.desc2,
    this.jumpUrl,
    this.reserveTotal,
    this.rid,
    this.state,
    this.stype,
    this.title,
    this.upMid,
  });

  Map? button;
  Map? desc1;
  Map? desc2;
  String? jumpUrl;
  int? reserveTotal;
  int? rid;
  int? state;
  int? stype;
  String? title;
  int? upMid;

  Reserve.fromJson(Map<String, dynamic> json) {
    button = json['button'];
    desc1 = json['desc1'];
    desc2 = json['desc2'];
    jumpUrl = json['jump_url'];
    reserveTotal = json['reserve_total'];
    rid = json['rid'];
    state = json['state'];
    state = json['state'];
    stype = json['stype'];
    title = json['title'];
    upMid = json['up_mid'];
  }
}

class Good {
  Good({
    this.headIcon,
    this.headText,
    this.items,
    this.jumpUrl,
  });

  String? headIcon;
  String? headText;
  List<GoodItem>? items;
  String? jumpUrl;

  Good.fromJson(Map<String, dynamic> json) {
    headIcon = json['head_icon'];
    headText = json['head_text'];
    items = json['items'].map<GoodItem>((e) => GoodItem.fromJson(e)).toList();
    jumpUrl = json['jump_url'];
  }
}

class GoodItem {
  GoodItem({
    this.brief,
    this.cover,
    this.id,
    this.jumpDesc,
    this.jumpUrl,
    this.name,
    this.price,
  });

  String? brief;
  String? cover;
  dynamic id;
  String? jumpDesc;
  String? jumpUrl;
  String? name;
  String? price;

  GoodItem.fromJson(Map<String, dynamic> json) {
    brief = json['brief'];
    cover = json['cover'];
    id = json['id'];
    jumpDesc = json['jump_desc'];
    jumpUrl = json['jump_url'];
    name = json['name'];
    price = json['price'];
  }
}

class DynamicDescModel {
  DynamicDescModel({
    this.richTextNodes,
    this.text,
  });

  List<RichTextNodeItem>? richTextNodes;
  String? text;

  DynamicDescModel.fromJson(Map<String, dynamic> json) {
    richTextNodes = json['rich_text_nodes'] != null
        ? json['rich_text_nodes']
            .map<RichTextNodeItem>((e) => RichTextNodeItem.fromJson(e))
            .toList()
        : [];
    text = json['text'];
  }
}

//
class DynamicMajorModel {
  DynamicMajorModel({
    this.archive,
    this.draw,
    this.ugcSeason,
    this.opus,
    this.pgc,
    this.liveRcmd,
    this.live,
    this.none,
    this.type,
    this.courses,
    this.common,
    this.music,
  });

  DynamicArchiveModel? archive;
  DynamicDrawModel? draw;
  DynamicArchiveModel? ugcSeason;
  DynamicOpusModel? opus;
  DynamicArchiveModel? pgc;
  DynamicLiveModel? liveRcmd;
  DynamicLive2Model? live;
  DynamicNoneModel? none;
  // MAJOR_TYPE_DRAW 图片
  // MAJOR_TYPE_ARCHIVE 视频
  // MAJOR_TYPE_OPUS 图文/文章
  String? type;
  Map? courses;
  Map? common;
  Map? music;

  DynamicMajorModel.fromJson(Map<String, dynamic> json) {
    archive = json['archive'] != null
        ? DynamicArchiveModel.fromJson(json['archive'])
        : null;
    draw =
        json['draw'] != null ? DynamicDrawModel.fromJson(json['draw']) : null;
    ugcSeason = json['ugc_season'] != null
        ? DynamicArchiveModel.fromJson(json['ugc_season'])
        : null;
    opus =
        json['opus'] != null ? DynamicOpusModel.fromJson(json['opus']) : null;
    pgc =
        json['pgc'] != null ? DynamicArchiveModel.fromJson(json['pgc']) : null;
    liveRcmd = json['live_rcmd'] != null
        ? DynamicLiveModel.fromJson(json['live_rcmd'])
        : null;
    live =
        json['live'] != null ? DynamicLive2Model.fromJson(json['live']) : null;
    none =
        json['none'] != null ? DynamicNoneModel.fromJson(json['none']) : null;
    type = json['type'];
    courses = json['courses'] ?? {};
    common = json['common'] ?? {};
    music = json['music'] ?? {};
  }
}

class DynamicTopicModel {
  DynamicTopicModel({
    this.id,
    this.jumpUrl,
    this.name,
  });

  int? id;
  String? jumpUrl;
  String? name;

  DynamicTopicModel.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    jumpUrl = json['jump_url'];
    name = json['name'];
  }
}

class DynamicArchiveModel {
  DynamicArchiveModel({
    this.aid,
    this.badge,
    this.bvid,
    this.cover,
    this.desc,
    this.disablePreview,
    this.durationText,
    this.jumpUrl,
    this.stat,
    this.title,
    this.type,
    this.epid,
    this.seasonId,
  });

  int? aid;
  Map? badge;
  String? bvid;
  String? cover;
  String? desc;
  int? disablePreview;
  String? durationText;
  String? jumpUrl;
  Stat? stat;
  String? title;
  int? type;
  int? epid;
  int? seasonId;

  DynamicArchiveModel.fromJson(Map<String, dynamic> json) {
    aid = _asInt(json['aid']);
    badge = json['badge'];
    final rawBvid = json['bvid'];
    bvid = rawBvid?.toString();
    cover = json['cover']?.toString();
    disablePreview = _asInt(json['disable_preview']);
    durationText = json['duration_text']?.toString();
    jumpUrl = json['jump_url']?.toString();
    stat = json['stat'] is Map
        ? Stat.fromJson(Map<String, dynamic>.from(json['stat'] as Map))
        : null;
    title = json['title']?.toString();
    type = _asInt(json['type']);
    epid = _asInt(json['ep_id'] ?? json['epid']);
    seasonId = _asInt(json['season_id']);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class DynamicDrawModel {
  DynamicDrawModel({
    this.id,
    this.items,
  });

  int? id;
  List<DynamicDrawItemModel>? items;

  DynamicDrawModel.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    // ignore: prefer_null_aware_operators
    items = json['items'] != null
        ? json['items']
            .map<DynamicDrawItemModel>((e) => DynamicDrawItemModel.fromJson(e))
            .toList()
        : null;
  }
}

class DynamicOpusModel {
  DynamicOpusModel({
    this.jumpUrl,
    this.pics,
    this.summary,
    this.title,
  });

  String? jumpUrl;
  List<OpusPicsModel>? pics;
  SummaryModel? summary;
  String? title;
  DynamicOpusModel.fromJson(Map<String, dynamic> json) {
    jumpUrl = json['jump_url']?.toString();
    final rawPics = json['pics'];
    pics = rawPics is List
        ? rawPics
            .whereType<Map>()
            .map((e) => OpusPicsModel.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <OpusPicsModel>[];
    summary = json['summary'] is Map
        ? SummaryModel.fromJson(Map<String, dynamic>.from(json['summary']))
        : null;
    title = json['title']?.toString();
  }
}

class SummaryModel {
  SummaryModel({
    this.richTextNodes,
    this.text,
  });

  List<RichTextNodeItem>? richTextNodes;
  String? text;

  SummaryModel.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['rich_text_nodes'];
    richTextNodes = rawNodes is List
        ? rawNodes
            .whereType<Map>()
            .map((e) => RichTextNodeItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <RichTextNodeItem>[];
    text = json['text']?.toString();
  }
}

class RichTextNodeItem {
  RichTextNodeItem({
    this.emoji,
    this.origText,
    this.text,
    this.type,
    this.rid,
  });
  Emoji? emoji;
  String? origText;
  String? text;
  String? type;
  String? rid;

  RichTextNodeItem.fromJson(Map<String, dynamic> json) {
    emoji = json['emoji'] != null ? Emoji.fromJson(json['emoji']) : null;
    origText = json['orig_text'];
    text = json['text'];
    type = json['type'];
    rid = json['rid'];
  }
}

class Emoji {
  Emoji({
    this.iconUrl,
    this.size,
    this.text,
    this.type,
  });

  String? iconUrl;
  double? size;
  String? text;
  int? type;
  Emoji.fromJson(Map<String, dynamic> json) {
    iconUrl = json['icon_url']?.toString();
    final rawSize = json['size'];
    size = rawSize is num
        ? rawSize.toDouble()
        : double.tryParse(rawSize?.toString() ?? '') ?? 1;
    text = json['text']?.toString();
    type = json['type'] is num
        ? (json['type'] as num).toInt()
        : int.tryParse(json['type']?.toString() ?? '');
  }
}

class DynamicNoneModel {
  DynamicNoneModel({
    this.tips,
  });
  String? tips;
  DynamicNoneModel.fromJson(Map<String, dynamic> json) {
    tips = json['tips'];
  }
}

class OpusPicsModel {
  OpusPicsModel({
    this.width,
    this.height,
    this.size,
    this.src,
    this.url,
  });

  int? width;
  int? height;
  int? size;
  String? src;
  String? url;

  OpusPicsModel.fromJson(Map<String, dynamic> json) {
    width = _asInt(json['width']);
    height = _asInt(json['height']);
    size = _asInt(json['size']) ?? 0;
    src = json['src']?.toString();
    url = json['url']?.toString();
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class DynamicDrawItemModel {
  DynamicDrawItemModel({
    this.height,
    this.size,
    this.src,
    this.tags,
    this.width,
  });
  int? height;
  int? size;
  String? src;
  List? tags;
  int? width;
  DynamicDrawItemModel.fromJson(Map<String, dynamic> json) {
    height = _asInt(json['height']);
    size = _asInt(json['size']);
    src = json['src']?.toString();
    tags = json['tags'] is List ? json['tags'] as List : <dynamic>[];
    width = _asInt(json['width']);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class DynamicLiveModel {
  DynamicLiveModel({
    this.content,
  });

  String? content;
  int? type;
  Map? livePlayInfo;
  int? uid;
  String? parentAreaName;
  int? roomId;
  String? liveId;
  int? liveStatus;
  String? cover;
  int? online;
  String? areaName;
  String? title;
  int? liveStartTime;
  Map? watchedShow;

  DynamicLiveModel.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    content = rawContent is String ? rawContent : null;
    final decoded = rawContent is Map
        ? Map<String, dynamic>.from(rawContent)
        : _decodeContent(content);
    if (decoded == null) {
      return;
    }
    final rawInfo = decoded['live_play_info'];
    final livePlayInfo = rawInfo is Map
        ? Map<String, dynamic>.from(rawInfo)
        : <String, dynamic>{};
    type = decoded['type'];
    uid = livePlayInfo['uid'];
    parentAreaName = livePlayInfo['parent_area_name'];
    roomId = livePlayInfo['room_id'];
    liveId = livePlayInfo['live_id'];
    liveStatus = livePlayInfo['live_status'];
    cover = livePlayInfo['cover'];
    online = livePlayInfo['online'];
    areaName = livePlayInfo['area_name'];
    title = livePlayInfo['title'];
    liveStartTime = livePlayInfo['live_start_time'];
    watchedShow = livePlayInfo['watched_show'] is Map
        ? Map<String, dynamic>.from(livePlayInfo['watched_show'])
        : null;
  }

  static Map<String, dynamic>? _decodeContent(String? content) {
    if (content == null || content.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(content);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}

class DynamicLive2Model {
  DynamicLive2Model({
    this.badge,
    this.cover,
    this.descFirst,
    this.descSecond,
    this.id,
    this.jumpUrl,
    this.liveState,
    this.reserveType,
    this.title,
  });

  Map? badge;
  String? cover;
  String? descFirst;
  String? descSecond;
  int? id;
  String? jumpUrl;
  int? liveState;
  int? reserveType;
  String? title;

  DynamicLive2Model.fromJson(Map<String, dynamic> json) {
    badge = json['badge'];
    cover = json['cover'];
    descFirst = json['desc_first'];
    descSecond = json['desc_second'];
    id = json['id'];
    jumpUrl = json['jump_url'];
    liveState = json['liv_state'];
    reserveType = json['reserve_type'];
    title = json['title'];
  }
}

// 动态状态 转发、评论、点赞
class ModuleStatModel {
  ModuleStatModel({
    this.comment,
    this.forward,
    this.like,
  });

  Comment? comment;
  ForWard? forward;
  Like? like;

  ModuleStatModel.fromJson(Map<String, dynamic> json) {
    comment = json['comment'] is Map
        ? Comment.fromJson(Map<String, dynamic>.from(json['comment']))
        : Comment();
    forward = json['forward'] is Map
        ? ForWard.fromJson(Map<String, dynamic>.from(json['forward']))
        : ForWard();
    like = json['like'] is Map
        ? Like.fromJson(Map<String, dynamic>.from(json['like']))
        : Like();
  }
}

// 动态状态 评论
class Comment {
  Comment({
    this.count,
    this.forbidden,
  });

  String? count;
  bool? forbidden;

  Comment.fromJson(Map<String, dynamic> json) {
    count = json['count'] == 0 ? null : json['count'].toString();
    forbidden = json['forbidden'];
  }
}

class ForWard {
  ForWard({this.count, this.forbidden});
  String? count;
  bool? forbidden;

  ForWard.fromJson(Map<String, dynamic> json) {
    count = json['count'] == 0 ? null : json['count'].toString();
    forbidden = json['forbidden'];
  }
}

// 动态状态 点赞
class Like {
  Like({
    this.count,
    this.forbidden,
    this.status,
  });

  String? count;
  bool? forbidden;
  bool? status;

  Like.fromJson(Map<String, dynamic> json) {
    count = json['count'] == 0 ? null : json['count'].toString();
    forbidden = json['forbidden'];
    status = json['status'];
  }
}

class Stat {
  Stat({
    this.danmaku,
    this.play,
  });

  String? danmaku;
  String? play;

  Stat.fromJson(Map<String, dynamic> json) {
    danmaku = json['danmaku'];
    play = json['play'];
  }
}
