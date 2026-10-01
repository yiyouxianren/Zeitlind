class BangumiInfoModel {
  BangumiInfoModel({
    this.activity,
    this.actors,
    this.alias,
    this.areas,
    this.bkgCover,
    this.cover,
    this.enableVt,
    this.episodes,
    this.evaluate,
    this.freya,
    this.jpTitle,
    this.link,
    this.mediaId,
    this.newEp,
    this.playStrategy,
    this.positive,
    this.publish,
    this.rating,
    this.record,
    this.rights,
    this.seasonId,
    this.seasonTitle,
    this.seasons,
    this.series,
    this.shareCopy,
    this.shareSubTitle,
    this.shareUrl,
    this.show,
    this.showSeasonType,
    this.squareCover,
    this.stat,
    this.status,
    this.styles,
    this.subTitle,
    this.title,
    this.total,
    this.type,
    this.userStatus,
    this.staff,
  });

  Map? activity;
  String? actors;
  String? alias;
  List? areas;
  String? bkgCover;
  String? cover;
  String? enableVt;
  List<EpisodeItem>? episodes;
  String? evaluate;
  Map? freya;
  String? jpTitle;
  String? link;
  int? mediaId;
  Map? newEp;
  Map? playStrategy;
  Map? positive;
  Map? publish;
  Map? rating;
  String? record;
  Map? rights;
  int? seasonId;
  String? seasonTitle;
  List? seasons;
  Map? series;
  String? shareCopy;
  String? shareSubTitle;
  String? shareUrl;
  Map? show;
  int? showSeasonType;
  String? squareCover;
  Map? stat;
  int? status;
  List? styles;
  String? subTitle;
  String? title;
  int? total;
  int? type;
  Map? userStatus;
  String? staff;

  BangumiInfoModel.fromJson(Map<String, dynamic> json) {
    activity = json['activity'];
    actors = json['actors'];
    alias = json['alias'];
    areas = json['areas'];
    bkgCover = json['bkg_cover'];
    cover = json['cover'];
    enableVt = json['enableVt'];
    final rawEpisodes = json['episodes'];
    episodes = rawEpisodes is List
        ? rawEpisodes
            .whereType<Map>()
            .map((item) => EpisodeItem.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList()
        : <EpisodeItem>[];
    evaluate = json['evaluate'];
    freya = json['freya'];
    jpTitle = json['jp_title'];
    link = json['link'];
    mediaId = _asInt(json['media_id']);
    newEp = json['new_ep'];
    playStrategy = json['play_strategy'];
    positive = json['positive'];
    publish = json['publish'];
    rating = json['rating'];
    record = json['record'];
    rights = json['rights'];
    seasonId = _asInt(json['season_id']);
    seasonTitle = json['season_title'];
    seasons = json['seasons'];
    series = json['series'];
    shareCopy = json['share_copy'];
    shareSubTitle = json['share_sub_title'];
    shareUrl = json['share_url'];
    show = json['show'];
    showSeasonType = json['show_season_type'];
    squareCover = json['square_cover'];
    stat = json['stat'];
    status = json['status'];
    styles = json['styles'];
    subTitle = json['sub_title'];
    title = json['title'];
    total = json['total'];
    type = json['type'];
    userStatus = json['user_status'];
    staff = json['staff'];
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class EpisodeItem {
  EpisodeItem({
    this.aid,
    this.badge,
    this.badgeInfo,
    this.badgeType,
    this.bvid,
    this.cid,
    this.cover,
    this.dimension,
    this.duration,
    this.enableVt,
    this.from,
    this.id,
    this.isViewHide,
    this.link,
    this.longTitle,
    this.pubTime,
    this.pv,
    this.releaseDate,
    this.rights,
    this.shareCopy,
    this.shareUrl,
    this.shortLink,
    this.skip,
    this.status,
    this.subtitle,
    this.title,
    this.vid,
  });

  int? aid;
  String? badge;
  Map? badgeInfo;
  int? badgeType;
  String? bvid;
  int? cid;
  String? cover;
  Map? dimension;
  int? duration;
  bool? enableVt;
  String? from;
  int? id;
  bool? isViewHide;
  String? link;
  String? longTitle;
  int? pubTime;
  int? pv;
  String? releaseDate;
  Map? rights;
  String? shareCopy;
  String? shareUrl;
  String? shortLink;
  Map? skip;
  int? status;
  String? subtitle;
  String? title;
  String? vid;

  EpisodeItem.fromJson(Map<String, dynamic> json) {
    aid = _asInt(json['aid']);
    badge = json['badge']?.toString().isNotEmpty == true
        ? json['badge'].toString()
        : null;
    badgeInfo = json['badge_info'];
    badgeType = _asInt(json['badge_type']);
    bvid = json['bvid']?.toString();
    cid = _asInt(json['cid']);
    cover = json['cover']?.toString();
    dimension = json['dimension'];
    duration = _asInt(json['duration']);
    enableVt = json['enable_vt'];
    from = json['from']?.toString();
    id = _asInt(json['id']);
    isViewHide = json['is_view_hide'];
    link = json['link']?.toString();
    longTitle = json['long_title']?.toString();
    pubTime = _asInt(json['pub_time']);
    pv = _asInt(json['pv']);
    releaseDate = json['release_date']?.toString();
    rights = json['rights'];
    shareCopy = json['share_copy']?.toString();
    shareUrl = json['share_url']?.toString();
    shortLink = json['short_link']?.toString();
    skip = json['skip'];
    status = _asInt(json['status']);
    subtitle = json['subtitle']?.toString();
    title = json['title']?.toString();
    vid = json['vid']?.toString();
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
