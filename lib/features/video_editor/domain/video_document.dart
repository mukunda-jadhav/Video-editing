import 'dart:math' as math;

enum VideoFilter { original, mono, vivid, warm, cool, cinema }

enum VideoEffect { none, vignette, soft, mirror, fade }

enum VideoTransition { cut, dissolve, wipe, slide, circle }

enum VideoFit { fill, fit }

enum VideoCanvas { original, landscape, portrait, square, social }

/// Bounds keep recipe history and simultaneous text filters suitable for phones.
/// Loading never truncates a saved project; users can remove items to fit.
abstract final class VideoEditingLimits {
  static const clips = 64;
  static const textLayers = 48;
  static const overlays = 12;
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
    this.positionX = 0,
    this.positionY = 0,
    this.fit = VideoFit.fill,
    this.filterIntensity = 1,
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.exposure = 0,
    this.cutoutOriginal,
    this.cutoutRecipe,
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

  /// Translation in canvas widths/heights. Zero retains legacy crop framing.
  final double positionX;
  final double positionY;
  final VideoFit fit;
  final double filterIntensity;
  final double brightness;
  final double contrast;
  final double saturation;
  final double exposure;
  final VideoClip? cutoutOriginal;
  final Map<String, dynamic>? cutoutRecipe;

  double get duration => (end - start) / speed;
  String get name => path.replaceAll('\\', '/').split('/').last;

  VideoClip copyWith({
    String? id,
    String? path,
    double? sourceDuration,
    int? width,
    int? height,
    bool? hasAudio,
    VideoClip? cutoutOriginal,
    Map<String, dynamic>? cutoutRecipe,
    bool clearCutoutOriginal = false,
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
    double? positionX,
    double? positionY,
    VideoFit? fit,
    double? filterIntensity,
    double? brightness,
    double? contrast,
    double? saturation,
    double? exposure,
  }) => VideoClip(
    id: id ?? this.id,
    path: path ?? this.path,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    start: start ?? this.start,
    end: end ?? this.end,
    speed: speed ?? this.speed,
    volume: volume ?? this.volume,
    width: width ?? this.width,
    height: height ?? this.height,
    hasAudio: hasAudio ?? this.hasAudio,
    filter: filter ?? this.filter,
    effect: effect ?? this.effect,
    transition: transition ?? this.transition,
    transitionDuration: transitionDuration ?? this.transitionDuration,
    cropX: cropX ?? this.cropX,
    cropY: cropY ?? this.cropY,
    zoom: zoom ?? this.zoom,
    positionX: positionX ?? this.positionX,
    positionY: positionY ?? this.positionY,
    fit: fit ?? this.fit,
    filterIntensity: filterIntensity ?? this.filterIntensity,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    exposure: exposure ?? this.exposure,
    cutoutOriginal: clearCutoutOriginal
        ? null
        : cutoutOriginal ?? this.cutoutOriginal,
    cutoutRecipe: clearCutoutOriginal
        ? null
        : cutoutRecipe == null
        ? this.cutoutRecipe
        : _boundedCutoutRecipe(cutoutRecipe),
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
    'positionX': positionX,
    'positionY': positionY,
    'fit': fit.name,
    'filterIntensity': filterIntensity,
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'exposure': exposure,
    'cutoutRecipe': cutoutRecipe,
    'cutoutOriginal': cutoutOriginal
        ?.copyWith(clearCutoutOriginal: true)
        .toJson(),
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
      zoom: _number(json['zoom'], 1, .1, 4),
      positionX: _number(json['positionX'], 0, -2, 2),
      positionY: _number(json['positionY'], 0, -2, 2),
      fit: _enum(VideoFit.values, json['fit'], VideoFit.fill),
      filterIntensity: _number(json['filterIntensity'], 1, 0, 1),
      brightness: _number(json['brightness'], 0, -.5, .5),
      contrast: _number(json['contrast'], 1, 0, 2),
      saturation: _number(json['saturation'], 1, 0, 2),
      exposure: _number(json['exposure'], 0, -2, 2),
      cutoutRecipe: json['cutoutRecipe'] is Map
          ? _boundedCutoutRecipe(
              Map<String, dynamic>.from(json['cutoutRecipe'] as Map),
            )
          : null,
      cutoutOriginal: json['cutoutOriginal'] is Map
          ? VideoClip.fromJson(
              Map<String, dynamic>.from(json['cutoutOriginal'] as Map)
                ..remove('cutoutOriginal'),
            )
          : null,
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
    this.centered = false,
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

  /// Old projects align within spare space; direct manipulation uses centers.
  final bool centered;

  VideoText copyWith({double? x, double? y, double? size, bool? centered}) =>
      VideoText(
        id: id,
        text: text,
        x: x ?? this.x,
        y: y ?? this.y,
        size: size ?? this.size,
        color: color,
        font: font,
        start: start,
        end: end,
        background: background,
        centered: centered ?? this.centered,
      );

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
    'centered': centered,
  };

  factory VideoText.fromJson(Map<String, dynamic> json) => VideoText(
    id: json['id'] as String,
    text: (json['text'] as String).substring(
      0,
      math.min(2000, (json['text'] as String).length),
    ),
    x: _number(json['x'], .5, -.5, 1.5),
    y: _number(json['y'], .82, -.5, 1.5),
    size: _number(json['size'], .065, .02, .5),
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
    centered: json['centered'] as bool? ?? false,
  );
}

class VideoOverlay {
  const VideoOverlay({
    this.id = 'overlay',
    this.originalPath,
    this.centered = false,
    required this.path,
    this.x = .75,
    this.y = .1,
    this.width = .22,
    this.opacity = 1,
    this.start = 0,
    this.end = 86400,
  });
  final String id;
  final String? originalPath;
  final bool centered;
  final String path;
  final double x;
  final double y;
  final double width;
  final double opacity;
  final double start;
  final double end;
  Map<String, dynamic> toJson() => {
    'id': id,
    'originalPath': originalPath,
    'centered': centered,
    'path': path,
    'x': x,
    'y': y,
    'width': width,
    'opacity': opacity,
    'start': start,
    'end': end,
  };
  VideoOverlay copyWith({
    double? x,
    double? y,
    double? width,
    double? opacity,
    double? start,
    double? end,
    bool? centered,
  }) => VideoOverlay(
    id: id,
    originalPath: originalPath,
    path: path,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    opacity: opacity ?? this.opacity,
    start: start ?? this.start,
    end: end ?? this.end,
    centered: centered ?? this.centered,
  );

  factory VideoOverlay.fromJson(Map<String, dynamic> json) => VideoOverlay(
    id: json['id'] as String? ?? json['path'] as String,
    originalPath: json['originalPath'] as String?,
    centered: json['centered'] as bool? ?? false,
    path: json['path'] as String,
    x: _number(json['x'], .75, -.5, 1.5),
    y: _number(json['y'], .1, -.5, 1.5),
    width: _number(json['width'], .22, .03, 2),
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
    VideoOverlay? overlay,
    List<VideoOverlay> overlays = const [],
    this.canvas = VideoCanvas.original,
    this.musicPath,
    this.musicVolume = .5,
    this.musicStart = 0,
  }) : clips = List.unmodifiable(clips),
       texts = List.unmodifiable(texts),
       overlays = List.unmodifiable(
         overlays.isNotEmpty
             ? overlays
             : overlay == null
             ? <VideoOverlay>[]
             : [overlay],
       );

  final String title;
  final List<VideoClip> clips;
  final List<VideoText> texts;
  final List<VideoOverlay> overlays;
  VideoOverlay? get overlay => overlays.firstOrNull;
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

  VideoDocument copyWith({
    String? title,
    List<VideoClip>? clips,
    List<VideoText>? texts,
    VideoOverlay? overlay,
    List<VideoOverlay>? overlays,
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
    overlays:
        overlays ??
        (removeOverlay
            ? <VideoOverlay>[]
            : overlay == null
            ? this.overlays
            : [overlay, ...this.overlays.skip(1)]),
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
    'overlays': overlays.map((layer) => layer.toJson()).toList(),
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
      overlays: (json['overlays'] as List<dynamic>? ?? [])
          .map(
            (layer) =>
                VideoOverlay.fromJson(Map<String, dynamic>.from(layer as Map)),
          )
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

Map<String, dynamic> _boundedCutoutRecipe(Map<String, dynamic> json) {
  final strokes = json['strokes'] as List<dynamic>? ?? [];
  if (strokes.length > 200) {
    throw const FormatException('A video cutout supports 200 brush strokes.');
  }
  final frozenStrokes = <Map<String, dynamic>>[];
  for (final raw in strokes) {
    if (raw is! Map || !['erase', 'restore'].contains(raw['mode'])) {
      throw const FormatException('Invalid video cutout brush stroke.');
    }
    final points = raw['points'];
    final radius = raw['radius'];
    if (points is! List ||
        points.isEmpty ||
        points.length > 4096 ||
        radius is! num ||
        !radius.isFinite ||
        radius <= 0 ||
        radius > 1) {
      throw const FormatException('Invalid video cutout brush bounds.');
    }
    final frozenPoints = <Map<String, double>>[];
    for (final point in points) {
      if (point is! Map || point['x'] is! num || point['y'] is! num) {
        throw const FormatException('Invalid video cutout brush point.');
      }
      final x = (point['x'] as num).toDouble();
      final y = (point['y'] as num).toDouble();
      if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
        throw const FormatException('Video cutout points must be normalized.');
      }
      frozenPoints.add(Map<String, double>.unmodifiable({'x': x, 'y': y}));
    }
    frozenStrokes.add(
      Map<String, dynamic>.unmodifiable({
        'mode': raw['mode'],
        'radius': radius.toDouble(),
        'points': List<Map<String, double>>.unmodifiable(frozenPoints),
      }),
    );
  }
  return Map<String, dynamic>.unmodifiable({
    'automatic': json['automatic'] as bool? ?? true,
    'backgroundColor': (json['backgroundColor'] as num?)?.toInt() ?? 0xff000000,
    'backgroundPath': json['backgroundPath'] as String?,
    'strokes': List<Map<String, dynamic>>.unmodifiable(frozenStrokes),
  });
}
