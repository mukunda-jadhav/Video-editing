import 'dart:math' as math;

enum VideoFilter { original, mono, vivid, warm, cool, cinema }

enum VideoEffect { none, vignette, soft, mirror, fade }

enum VideoTransition { cut, dissolve, wipe, slide, circle }

enum VideoCanvas { original, landscape, portrait, square, social }

/// Bounds keep recipe history and simultaneous text filters suitable for phones.
/// Loading never truncates a saved project; users can remove items to fit.
abstract final class VideoEditingLimits {
  static const clips = 64;
  static const textLayers = 48;
}

/// Immutable, nondestructive recipe. Times are seconds in the source media;
/// overlays use seconds in the final edited sequence. Media stays in files.
class VideoClip {
  const VideoClip({
    required this.id,
    required this.path,
    required this.sourceDuration,
    required this.end,
    this.start = 0,
    this.speed = 1,
    this.volume = 1,
    this.width = 1920,
    this.height = 1080,
    this.hasAudio = true,
    this.filter = VideoFilter.original,
    this.effect = VideoEffect.none,
    this.transition = VideoTransition.cut,
    this.transitionDuration = .5,
    this.cropX = .5,
    this.cropY = .5,
    this.zoom = 1,
  });

  final String id;
  final String path;
  final double sourceDuration;
  final double start;
  final double end;
  final double speed;
  final double volume;
  final int width;
  final int height;
  final bool hasAudio;
  final VideoFilter filter;
  final VideoEffect effect;

  /// Transition from this clip to the following one.
  final VideoTransition transition;
  final double transitionDuration;
  final double cropX;
  final double cropY;
  final double zoom;

  double get duration => (end - start) / speed;
  String get name => path.replaceAll('\\', '/').split('/').last;

  VideoClip copyWith({
    String? id,
    double? start,
    double? end,
    double? speed,
    double? volume,
    VideoFilter? filter,
    VideoEffect? effect,
    VideoTransition? transition,
    double? transitionDuration,
    double? cropX,
    double? cropY,
    double? zoom,
  }) => VideoClip(
    id: id ?? this.id,
    path: path,
    sourceDuration: sourceDuration,
    start: start ?? this.start,
    end: end ?? this.end,
    speed: speed ?? this.speed,
    volume: volume ?? this.volume,
    width: width,
    height: height,
    hasAudio: hasAudio,
    filter: filter ?? this.filter,
    effect: effect ?? this.effect,
    transition: transition ?? this.transition,
    transitionDuration: transitionDuration ?? this.transitionDuration,
    cropX: cropX ?? this.cropX,
    cropY: cropY ?? this.cropY,
    zoom: zoom ?? this.zoom,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'sourceDuration': sourceDuration,
    'start': start,
    'end': end,
    'speed': speed,
    'volume': volume,
    'width': width,
    'height': height,
    'hasAudio': hasAudio,
    'filter': filter.name,
    'effect': effect.name,
    'transition': transition.name,
    'transitionDuration': transitionDuration,
    'cropX': cropX,
    'cropY': cropY,
    'zoom': zoom,
  };

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    final duration = _number(json['sourceDuration'], 1, .05, 86400);
    final start = _number(json['start'], 0, 0, duration - .04);
    return VideoClip(
      id: json['id'] as String,
      path: json['path'] as String,
      sourceDuration: duration,
      start: start,
      end: _number(json['end'], duration, start + .04, duration),
      speed: _number(json['speed'], 1, .25, 4),
      volume: _number(json['volume'], 1, 0, 2),
      width: (json['width'] as num?)?.toInt() ?? 1920,
      height: (json['height'] as num?)?.toInt() ?? 1080,
      hasAudio: json['hasAudio'] as bool? ?? true,
      filter: _enum(VideoFilter.values, json['filter'], VideoFilter.original),
      effect: _enum(VideoEffect.values, json['effect'], VideoEffect.none),
      transition: _enum(
        VideoTransition.values,
        json['transition'],
        VideoTransition.cut,
      ),
      transitionDuration: _number(json['transitionDuration'], .5, .1, 2),
      cropX: _number(json['cropX'], .5, 0, 1),
      cropY: _number(json['cropY'], .5, 0, 1),
      zoom: _number(json['zoom'], 1, 1, 3),
    );
  }
}

class VideoText {
  const VideoText({
    required this.id,
    required this.text,
    this.x = .5,
    this.y = .82,
    this.size = .065,
    this.color = 0xFFFFFFFF,
    this.font = 'StudioSans',
    this.start = 0,
    this.end = 86400,
    this.background = true,
  });
  final String id;
  final String text;
  final double x;
  final double y;
  final double size;
  final int color;
  final String font;
  final double start;
  final double end;
  final bool background;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'size': size,
    'color': color,
    'font': font,
    'start': start,
    'end': end,
    'background': background,
  };

  factory VideoText.fromJson(Map<String, dynamic> json) => VideoText(
    id: json['id'] as String,
    text: (json['text'] as String).substring(
      0,
      math.min(2000, (json['text'] as String).length),
    ),
    x: _number(json['x'], .5, 0, 1),
    y: _number(json['y'], .82, 0, 1),
    size: _number(json['size'], .065, .02, .25),
    color: (json['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
    font:
        const [
          'StudioSans',
          'StudioSerif',
          'StudioMono',
          'StudioScript',
          'StudioDisplay',
        ].contains(json['font'])
        ? json['font'] as String
        : 'StudioSans',
    start: _number(json['start'], 0, 0, 86400),
    end: _number(json['end'], 86400, 0, 86400),
    background: json['background'] as bool? ?? true,
  );
}

class VideoOverlay {
  const VideoOverlay({
    required this.path,
    this.x = .75,
    this.y = .1,
    this.width = .22,
    this.opacity = 1,
    this.start = 0,
    this.end = 86400,
  });
  final String path;
  final double x;
  final double y;
  final double width;
  final double opacity;
  final double start;
  final double end;
  Map<String, dynamic> toJson() => {
    'path': path,
    'x': x,
    'y': y,
    'width': width,
    'opacity': opacity,
    'start': start,
    'end': end,
  };
  factory VideoOverlay.fromJson(Map<String, dynamic> json) => VideoOverlay(
    path: json['path'] as String,
    x: _number(json['x'], .75, 0, 1),
    y: _number(json['y'], .1, 0, 1),
    width: _number(json['width'], .22, .05, 1),
    opacity: _number(json['opacity'], 1, 0, 1),
    start: _number(json['start'], 0, 0, 86400),
    end: _number(json['end'], 86400, 0, 86400),
  );
}

class VideoDocument {
  VideoDocument({
    this.title = 'My video',
    List<VideoClip> clips = const [],
    List<VideoText> texts = const [],
    this.overlay,
    this.canvas = VideoCanvas.original,
    this.musicPath,
    this.musicVolume = .5,
    this.musicStart = 0,
  }) : clips = List.unmodifiable(clips),
       texts = List.unmodifiable(texts);

  final String title;
  final List<VideoClip> clips;
  final List<VideoText> texts;
  final VideoOverlay? overlay;
  final VideoCanvas canvas;
  final String? musicPath;
  final double musicVolume;
  final double musicStart;

  double transitionAt(int index) {
    if (index < 0 ||
        index >= clips.length - 1 ||
        clips[index].transition == VideoTransition.cut) {
      return 0;
    }
    return math.min(
      clips[index].transitionDuration,
      math.min(clips[index].duration / 2, clips[index + 1].duration / 2),
    );
  }

  double get duration {
    var result = 0.0;
    for (var i = 0; i < clips.length; i++) {
      result += clips[i].duration - transitionAt(i);
    }
    return result;
  }

  double get aspectRatio => switch (canvas) {
    VideoCanvas.original =>
      clips.isEmpty ? 16 / 9 : clips.first.width / clips.first.height,
    VideoCanvas.landscape => 16 / 9,
    VideoCanvas.portrait => 9 / 16,
    VideoCanvas.square => 1,
    VideoCanvas.social => 4 / 5,
  };

  bool get usesProTools =>
      clips.any(
        (c) =>
            c.filter == VideoFilter.cinema ||
            c.effect == VideoEffect.soft ||
            c.transition == VideoTransition.slide ||
            c.transition == VideoTransition.circle,
      ) ||
      texts.any((t) => t.font == 'StudioScript' || t.font == 'StudioDisplay');

  VideoDocument copyWith({
    String? title,
    List<VideoClip>? clips,
    List<VideoText>? texts,
    VideoOverlay? overlay,
    bool removeOverlay = false,
    VideoCanvas? canvas,
    String? musicPath,
    bool removeMusic = false,
    double? musicVolume,
    double? musicStart,
  }) => VideoDocument(
    title: title ?? this.title,
    clips: clips ?? this.clips,
    texts: texts ?? this.texts,
    overlay: removeOverlay ? null : overlay ?? this.overlay,
    canvas: canvas ?? this.canvas,
    musicPath: removeMusic ? null : musicPath ?? this.musicPath,
    musicVolume: musicVolume ?? this.musicVolume,
    musicStart: musicStart ?? this.musicStart,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'type': 'video',
    'title': title,
    'clips': clips.map((c) => c.toJson()).toList(),
    'texts': texts.map((t) => t.toJson()).toList(),
    'overlay': overlay?.toJson(),
    'canvas': canvas.name,
    'musicPath': musicPath,
    'musicVolume': musicVolume,
    'musicStart': musicStart,
  };

  factory VideoDocument.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 || json['type'] != 'video') {
      throw const FormatException('Unsupported video project version.');
    }
    return VideoDocument(
      title: json['title'] as String? ?? 'My video',
      clips: (json['clips'] as List<dynamic>? ?? [])
          .map((c) => VideoClip.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
      texts: (json['texts'] as List<dynamic>? ?? [])
          .map((t) => VideoText.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      overlay: json['overlay'] == null
          ? null
          : VideoOverlay.fromJson(
              Map<String, dynamic>.from(json['overlay'] as Map),
            ),
      canvas: _enum(VideoCanvas.values, json['canvas'], VideoCanvas.original),
      musicPath: json['musicPath'] as String?,
      musicVolume: _number(json['musicVolume'], .5, 0, 2),
      musicStart: _number(json['musicStart'], 0, 0, 86400),
    );
  }
}

double _number(dynamic value, double fallback, double min, double max) {
  final number = value is num ? value.toDouble() : fallback;
  return number.isFinite ? number.clamp(min, max) : fallback;
}

T _enum<T extends Enum>(List<T> values, dynamic name, T fallback) =>
    values.where((v) => v.name == name).firstOrNull ?? fallback;
