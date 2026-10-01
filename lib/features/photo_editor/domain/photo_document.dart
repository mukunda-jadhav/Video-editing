import 'dart:math' as math;

double _number(Object? value, double fallback) =>
    value is num && value.isFinite ? value.toDouble() : fallback;

/// A non-destructive, versioned edit recipe. Media stays in app-owned storage.
class PhotoDocument {
  PhotoDocument({
    this.title = 'Untitled photo',
    this.imagePath,
    this.originalImagePath,
    this.backgroundPath,
    this.width = 1080,
    this.height = 1080,
    this.backgroundColor = 0xff202431,
    this.rotation = 0,
    this.flipHorizontal = false,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 1,
    this.cropBottom = 1,
    this.brightness = 1,
    this.contrast = 1,
    this.saturation = 1,
    this.exposure = 0,
    this.blur = 0,
    this.filter = 'Original',
    this.imageFit = 'cover',
    this.imageX = 0,
    this.imageY = 0,
    this.imageScale = 1,
    this.imageRotation = 0,
    this.filterIntensity = 1,
    List<PhotoLayer>? layers,
  }) : layers = layers ?? [];

  String title;
  String? imagePath;
  String? originalImagePath;
  String? backgroundPath;
  int width;
  int height;
  int backgroundColor;
  int rotation;
  bool flipHorizontal;
  double cropLeft;
  double cropTop;
  double cropRight;
  double cropBottom;
  double brightness;
  double contrast;
  double saturation;
  double exposure;
  double blur;
  String filter;
  String imageFit;

  /// Position is a canvas-normalized center offset, preserving old recipes.
  double imageX;
  double imageY;
  double imageScale;
  double imageRotation;
  double filterIntensity;
  List<PhotoLayer> layers;

  factory PhotoDocument.fromJson(Map<String, dynamic> json) {
    if (json['version'] != null && json['version'] != 1) {
      throw const FormatException(
        'Update FrameLab to open this photo project version.',
      );
    }
    final savedLayers = json['layers'] as List? ?? [];
    if (savedLayers.length > maxLayers) {
      throw const FormatException(
        'This photo project exceeds the supported layer limit.',
      );
    }
    final left = _number(json['cropLeft'], 0).clamp(0.0, .95);
    final top = _number(json['cropTop'], 0).clamp(0.0, .95);
    return PhotoDocument(
      title: json['title'] as String? ?? 'Untitled photo',
      imagePath: json['imagePath'] as String?,
      originalImagePath: json['originalImagePath'] as String?,
      backgroundPath: json['backgroundPath'] as String?,
      width: _number(json['width'], 1080).round().clamp(64, 4096),
      height: _number(json['height'], 1080).round().clamp(64, 4096),
      backgroundColor: (json['backgroundColor'] as num?)?.toInt() ?? 0xff202431,
      rotation: _number(json['rotation'], 0).round() % 4,
      flipHorizontal: json['flipHorizontal'] == true,
      cropLeft: left,
      cropTop: top,
      cropRight: _number(json['cropRight'], 1).clamp(left + .05, 1.0),
      cropBottom: _number(json['cropBottom'], 1).clamp(top + .05, 1.0),
      brightness: _number(json['brightness'], 1).clamp(0, 2),
      contrast: _number(json['contrast'], 1).clamp(0, 2),
      saturation: _number(json['saturation'], 1).clamp(0, 2),
      exposure: _number(json['exposure'], 0).clamp(-2, 2),
      blur: _number(json['blur'], 0).clamp(0, 30),
      filter: json['filter'] as String? ?? 'Original',
      imageFit: json['imageFit'] == 'contain' ? 'contain' : 'cover',
      imageX: _number(json['imageX'], 0).clamp(-2, 2),
      imageY: _number(json['imageY'], 0).clamp(-2, 2),
      imageScale: _number(json['imageScale'], 1).clamp(.05, 5),
      imageRotation: _number(json['imageRotation'], 0),
      filterIntensity: _number(json['filterIntensity'], 1).clamp(0, 1),
      layers: savedLayers
          .whereType<Map<Object?, Object?>>()
          .map((item) => PhotoLayer.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  /// Keeps compositing memory and editable overlay complexity bounded on phones.
  static const maxLayers = 48;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'title': title,
    'imagePath': imagePath,
    'originalImagePath': originalImagePath,
    'backgroundPath': backgroundPath,
    'width': width,
    'height': height,
    'backgroundColor': backgroundColor,
    'rotation': rotation,
    'flipHorizontal': flipHorizontal,
    'cropLeft': cropLeft,
    'cropTop': cropTop,
    'cropRight': cropRight,
    'cropBottom': cropBottom,
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'exposure': exposure,
    'blur': blur,
    'filter': filter,
    'imageFit': imageFit,
    'imageX': imageX,
    'imageY': imageY,
    'imageScale': imageScale,
    'imageRotation': imageRotation,
    'filterIntensity': filterIntensity,
    'layers': layers.map((layer) => layer.toJson()).toList(),
  };

  PhotoDocument clone() => PhotoDocument.fromJson(toJson());

  /// Limits output pixels while preserving the requested aspect ratio.
  (int, int) exportSize() {
    const maxEdge = 4096;
    final scale = math.min(1.0, maxEdge / math.max(width, height));
    return (
      math.max(1, (width * scale).round()),
      math.max(1, (height * scale).round()),
    );
  }
}

class PhotoLayer {
  PhotoLayer({
    required this.id,
    this.kind = 'text',
    this.x = .1,
    this.y = .4,
    this.width = .8,
    this.height = .15,
    this.text = 'Your story',
    this.color = 0xffffffff,
    this.fontSize = .08,
    this.fontFamily = 'StudioSans',
    this.bold = true,
    this.rotation = 0,
    this.opacity = 1,
    this.path,
    this.originalPath,
  });

  String id;
  String kind;
  double x;
  double y;
  double width;
  double height;
  String text;
  int color;
  double fontSize;
  String fontFamily;
  bool bold;
  double rotation;
  double opacity;
  String? path;
  String? originalPath;

  factory PhotoLayer.fromJson(Map<String, dynamic> json) => PhotoLayer(
    id:
        json['id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    kind: json['kind'] as String? ?? 'text',
    x: _number(json['x'], .1).clamp(-2, 2),
    y: _number(json['y'], .4).clamp(-2, 2),
    width: _number(json['width'], .8).clamp(.01, 5),
    height: _number(json['height'], .15).clamp(.01, 5),
    text: json['text'] as String? ?? '',
    color: (json['color'] as num?)?.toInt() ?? 0xffffffff,
    fontSize: _number(json['fontSize'], .08).clamp(.01, .5),
    fontFamily: json['fontFamily'] as String? ?? 'StudioSans',
    bold: json['bold'] != false,
    rotation: _number(json['rotation'], 0),
    opacity: _number(json['opacity'], 1).clamp(0, 1),
    path: json['path'] as String?,
    originalPath: json['originalPath'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'text': text,
    'color': color,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'bold': bold,
    'rotation': rotation,
    'opacity': opacity,
    'path': path,
    'originalPath': originalPath,
  };
}

/// Bounded recipe history: no full-resolution images are retained for undo.
class PhotoHistory {
  PhotoHistory(PhotoDocument initial) : _states = [initial.clone()];
  final List<PhotoDocument> _states;
  int _index = 0;
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _states.length - 1;
  void commit(PhotoDocument document) {
    _states.removeRange(_index + 1, _states.length);
    _states.add(document.clone());
    if (_states.length > 40) _states.removeAt(0);
    _index = _states.length - 1;
  }

  PhotoDocument undo() {
    if (canUndo) _index--;
    return _states[_index].clone();
  }

  PhotoDocument redo() {
    if (canRedo) _index++;
    return _states[_index].clone();
  }
}
