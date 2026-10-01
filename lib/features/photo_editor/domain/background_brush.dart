import 'dart:ui';

/// Brush positions are normalized to the unrotated source image, so preview
/// zoom and export resolution never change the area being edited.
enum BackgroundBrushMode { erase, restore }

class BackgroundBrushStroke {
  BackgroundBrushStroke({
    required this.mode,
    required this.radius,
    required Iterable<Offset> points,
  }) : points = List.unmodifiable(points);

  factory BackgroundBrushStroke.fromMap(Map<String, dynamic> map) {
    final mode = switch (map['mode']) {
      'erase' => BackgroundBrushMode.erase,
      'restore' => BackgroundBrushMode.restore,
      _ => throw const FormatException('Unknown background brush mode.'),
    };
    final rawRadius = map['radius'];
    if (rawRadius is! num || !rawRadius.isFinite) {
      throw const FormatException('A background brush needs a finite radius.');
    }
    final rawPoints = map['points'];
    if (rawPoints is! List || rawPoints.isEmpty || rawPoints.length > 4096) {
      throw const FormatException('A background brush needs 1–4096 points.');
    }
    final points = <Offset>[];
    for (final rawPoint in rawPoints) {
      if (rawPoint is! Map) {
        throw const FormatException('Invalid background brush point.');
      }
      final x = rawPoint['x'];
      final y = rawPoint['y'];
      if (x is! num ||
          y is! num ||
          !x.isFinite ||
          !y.isFinite ||
          x < 0 ||
          x > 1 ||
          y < 0 ||
          y > 1) {
        throw const FormatException(
          'Brush points must be finite and normalized.',
        );
      }
      points.add(Offset(x.toDouble(), y.toDouble()));
    }
    return BackgroundBrushStroke(
      mode: mode,
      radius: rawRadius.toDouble().clamp(.001, 1.0),
      points: points,
    );
  }

  final BackgroundBrushMode mode;

  /// Radius relative to the shortest image edge.
  final double radius;
  final List<Offset> points;

  Map<String, dynamic> toMap() => {
    'mode': mode.name,
    'radius': radius,
    'points': [
      for (final point in points) {'x': point.dx, 'y': point.dy},
    ],
  };
}

class BackgroundBrushHistory {
  static const maxStrokes = 200;
  final List<BackgroundBrushStroke> _strokes = [];
  final List<BackgroundBrushStroke> _redo = [];
  List<BackgroundBrushStroke> get strokes => List.unmodifiable(_strokes);
  bool get canUndo => _strokes.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isFull => _strokes.length >= maxStrokes;

  bool add(BackgroundBrushStroke stroke) {
    if (isFull || stroke.points.isEmpty) return false;
    _strokes.add(stroke);
    _redo.clear();
    return true;
  }

  void undo() {
    if (canUndo) _redo.add(_strokes.removeLast());
  }

  void redo() {
    if (canRedo && !isFull) _strokes.add(_redo.removeLast());
  }
}
