import 'dart:io';

/// The way in which the video was originally loaded.
///
/// This has nothing to do with the video's file type. It's just the place
/// from which the video is fetched from.
enum DataSourceType {
  /// The video was included in the app's asset files.
  asset,

  /// The video was downloaded from the internet.
  network,

  /// The video was loaded off of the local filesystem.
  file,

  /// The video is available via contentUri. Android only.
  contentUri,
}

class DataSource {
  File? file;
  String? videoSource;
  String? audioSource;
  String? subFiles;
  final bool audioOnly;
  DataSourceType type;
  Map<String, String>? httpHeaders; // for headers
  DataSource({
    this.file,
    this.videoSource,
    this.audioSource,
    this.subFiles,
    this.audioOnly = false,
    required this.type,
    this.httpHeaders,
  })  : assert(!audioOnly || (audioSource != null && audioSource != '')),
        assert(audioOnly ||
            (type == DataSourceType.file && file != null) ||
            (videoSource != null && videoSource != ''));

  String get primarySource {
    if (audioOnly) {
      return audioSource!;
    }
    if (type == DataSourceType.file) {
      return file!.path;
    }
    return videoSource!;
  }

  DataSource copyWith({
    File? file,
    String? videoSource,
    String? audioSource,
    String? subFiles,
    bool? audioOnly,
    DataSourceType? type,
    Map<String, String>? httpHeaders,
  }) {
    return DataSource(
      file: file ?? this.file,
      videoSource: videoSource ?? this.videoSource,
      audioSource: audioSource ?? this.audioSource,
      subFiles: subFiles ?? this.subFiles,
      audioOnly: audioOnly ?? this.audioOnly,
      type: type ?? this.type,
      httpHeaders: httpHeaders ?? this.httpHeaders,
    );
  }
}
