import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/background_refine_renderer.dart';
import '../domain/background_brush.dart';

/// Returns a private local PNG path on Apply, null on Cancel. The caller keeps
/// originalPath to allow restoring areas removed by automatic segmentation.
class BackgroundRefineScreen extends StatefulWidget {
  const BackgroundRefineScreen({
    super.key,
    required this.originalPath,
    this.initialMaskPath,
    this.onApplied,
    this.initialStrokes = const [],
  });
  final String originalPath;
  final String? initialMaskPath;
  final ValueChanged<List<BackgroundBrushStroke>>? onApplied;
  final List<BackgroundBrushStroke> initialStrokes;

  @override
  State<BackgroundRefineScreen> createState() => _BackgroundRefineScreenState();
}

class _BackgroundRefineScreenState extends State<BackgroundRefineScreen> {
  final _history = BackgroundBrushHistory();
  final _transform = TransformationController();
  BackgroundRefineSource? _source;
  BackgroundBrushMode _mode = BackgroundBrushMode.erase;
  bool _zoom = false;
  bool _saving = false;
  String? _error;
  double _radius = .035;
  int? _pointer;
  final List<Offset> _points = [];
  Offset? _cursor;
  Rect _imageRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    for (final stroke in widget.initialStrokes) {
      _history.add(stroke);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final source = await BackgroundRefineSource.load(
        widget.originalPath,
        initialMaskPath: widget.initialMaskPath,
      );
      if (!mounted) {
        source.dispose();
        return;
      }
      setState(() => _source = source);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  List<BackgroundBrushStroke> get _strokes => [
    ..._history.strokes,
    if (_points.isNotEmpty)
      BackgroundBrushStroke(mode: _mode, radius: _radius, points: _points),
  ];

  void _begin(PointerDownEvent event) {
    if (_zoom || _saving || _pointer != null || _source == null) return;
    if (_history.isFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apply these 200 strokes, then reopen to continue refining.',
          ),
        ),
      );
      return;
    }
    final point = backgroundRefinePoint(event.localPosition, _imageRect);
    if (point == null) return;
    setState(() {
      _pointer = event.pointer;
      _points.add(point);
      _cursor = event.localPosition;
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _points.isEmpty) return;
    final point = backgroundRefinePoint(event.localPosition, _imageRect);
    // Ignore excursions beyond the photo so a re-entry never paints a line
    // across the image from a clamped off-canvas point.
    if (point == null) {
      _finish();
      return;
    }
    final distance = Offset(
      (point.dx - _points.last.dx) * _imageRect.width,
      (point.dy - _points.last.dy) * _imageRect.height,
    ).distance;
    if (distance < .75) return;
    if (_points.length >= 1024) {
      _finish();
      return;
    }
    setState(() {
      _points.add(point);
      _cursor = event.localPosition;
    });
  }

  void _finish() {
    if (_pointer == null) return;
    setState(() {
      _history.add(
        BackgroundBrushStroke(mode: _mode, radius: _radius, points: _points),
      );
      _pointer = null;
      _points.clear();
      _cursor = null;
    });
  }

  Future<void> _apply() async {
    if (_source == null || _saving) return;
    _finish();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final path = await saveRefinedBackground(
        originalPath: widget.originalPath,
        initialMaskPath: widget.initialMaskPath,
        outputSize: _source!.outputSize,
        strokes: _history.strokes,
      );
      if (mounted) {
        widget.onApplied?.call(_history.strokes);
        Navigator.of(context).pop<String>(path);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    _source?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cancel refinement',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Refine cutout',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Undo brush',
              icon: const Icon(Icons.undo_rounded),
              onPressed: !_saving && _history.canUndo
                  ? () => setState(_history.undo)
                  : null,
            ),
            IconButton(
              tooltip: 'Redo brush',
              icon: const Icon(Icons.redo_rounded),
              onPressed: !_saving && _history.canRedo
                  ? () => setState(_history.redo)
                  : null,
            ),
            IconButton(
              tooltip: 'Apply cutout',
              onPressed: source == null || _saving ? null : _apply,
              icon: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              Expanded(
                child: source == null
                    ? Center(
                        child: _error == null
                            ? const CircularProgressIndicator()
                            : const Text('Unable to open this photo.'),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.biggest;
                          _imageRect = backgroundRefineImageRect(
                            size,
                            Size(
                              source.original.width.toDouble(),
                              source.original.height.toDouble(),
                            ),
                          );
                          return ClipRect(
                            child: InteractiveViewer(
                              transformationController: _transform,
                              minScale: 1,
                              maxScale: 8,
                              panEnabled: _zoom && !_saving,
                              scaleEnabled: _zoom && !_saving,
                              child: Listener(
                                onPointerDown: _begin,
                                onPointerMove: _move,
                                onPointerUp: (event) {
                                  if (event.pointer == _pointer) _finish();
                                },
                                onPointerCancel: (event) {
                                  if (event.pointer == _pointer) _finish();
                                },
                                child: Semantics(
                                  label: _zoom
                                      ? 'Zoom and pan photo'
                                      : '${_mode.name} background brush canvas',
                                  child: CustomPaint(
                                    key: const ValueKey(
                                      'background-refine-canvas',
                                    ),
                                    size: size,
                                    painter: BackgroundRefinePainter(
                                      original: source.original,
                                      initial: source.initial,
                                      strokes: _strokes,
                                      imageRect: _imageRect,
                                      cursor: _cursor,
                                      cursorRadius:
                                          _radius *
                                          math.min(
                                            _imageRect.width,
                                            _imageRect.height,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (source != null)
                Container(
                  color: AppColors.surface,
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _saving
                            ? 'Saving cutout on this device…'
                            : _zoom
                            ? 'Pinch to zoom. Drag to pan. Select a brush to edit.'
                            : _mode == BackgroundBrushMode.erase
                            ? 'Brush over unwanted areas to erase.'
                            : 'Brush to restore the original photo.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      if (source.downsampled)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Refined output: ${source.outputSize.width.toInt()} × ${source.outputSize.height.toInt()} px (4096 px / 8 MP limit)',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (!_zoom)
                        Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('Brush size')),
                                Text(
                                  '${(_radius * 2 * math.min(source.outputSize.width, source.outputSize.height)).round()} px',
                                ),
                              ],
                            ),
                            Slider(
                              semanticFormatterCallback: (value) =>
                                  '${(value * 2 * math.min(source.outputSize.width, source.outputSize.height)).round()} pixels',
                              value: _radius,
                              min: .003,
                              max: .15,
                              onChanged: _saving
                                  ? null
                                  : (value) {
                                      _finish();
                                      setState(() => _radius = value);
                                    },
                            ),
                          ],
                        ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _tool(
                              'Erase',
                              Icons.auto_fix_off_outlined,
                              !_zoom && _mode == BackgroundBrushMode.erase,
                              () {
                                _finish();
                                setState(() {
                                  _zoom = false;
                                  _mode = BackgroundBrushMode.erase;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            _tool(
                              'Restore',
                              Icons.restore_rounded,
                              !_zoom && _mode == BackgroundBrushMode.restore,
                              () {
                                _finish();
                                setState(() {
                                  _zoom = false;
                                  _mode = BackgroundBrushMode.restore;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            _tool('Zoom', Icons.zoom_in_rounded, _zoom, () {
                              _finish();
                              setState(() => _zoom = true);
                            }),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Reset zoom',
                              onPressed: _saving
                                  ? null
                                  : () {
                                      _finish();
                                      _transform.value = Matrix4.identity();
                                    },
                              icon: const Icon(Icons.fit_screen_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tool(
    String label,
    IconData icon,
    bool selected,
    VoidCallback action,
  ) => Semantics(
    selected: selected,
    child: FilledButton.tonalIcon(
      onPressed: _saving ? null : action,
      style: FilledButton.styleFrom(
        minimumSize: const Size(96, 48),
        backgroundColor: selected ? AppColors.primary : AppColors.surfaceRaised,
        foregroundColor: selected ? AppColors.onPrimary : AppColors.text,
      ),
      icon: Icon(icon, size: 20),
      label: Text(label),
    ),
  );
}
