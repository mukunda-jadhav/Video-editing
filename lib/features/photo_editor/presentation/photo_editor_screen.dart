import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../data/photo_renderer.dart';
import '../domain/photo_document.dart';

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({
    super.key,
    this.initialData,
    required this.onSave,
    required this.removeBackground,
    required this.exportBytes,
    required this.pickImage,
  });
  final Map<String, dynamic>? initialData;
  final Future<void> Function(Map<String, dynamic>, String, String?) onSave;
  final Future<String> Function(String) removeBackground;
  final Future<String> Function(Uint8List, String) exportBytes;
  final Future<String?> Function() pickImage;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen>
    with WidgetsBindingObserver {
  late PhotoDocument _document;
  late PhotoHistory _history;
  PhotoComposition? _composition;
  String _tool = 'Adjust';
  String? _selectedId;
  bool _busy = false;
  bool _loadingMedia = false;
  bool _pendingMedia = false;
  bool _saving = false;
  bool _allowExit = false;
  String? _error;
  int _revision = 0;
  int _editVersion = 0;
  int _savedVersion = 0;
  final _previewCache = PhotoPreviewCache(maxEdge: 1200);
  String? _mediaKey;
  Timer? _saveTimer;
  Future<void>? _saveFuture;
  Size _canvasSize = Size.zero;
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'Photo canvas');

  static const _colors = [
    0xffffffff,
    0xff101116,
    0xffb4a0ff,
    0xffd4ef89,
    0xfffca98d,
    0xffa9d7e4,
    0xffff577f,
    0xffffcf5c,
    0xff386d57,
    0x00000000,
  ];
  static const _tools = <(String, IconData)>[
    ('Adjust', Icons.tune_rounded),
    ('Crop', Icons.crop_rounded),
    ('Filters', Icons.filter_vintage_outlined),
    ('Text', Icons.text_fields_rounded),
    ('Stickers', Icons.interests_outlined),
    ('Background', Icons.wallpaper_rounded),
    ('Layout', Icons.aspect_ratio_rounded),
    ('Layers', Icons.layers_outlined),
  ];

  PhotoLayer? get _selected {
    for (final layer in _document.layers) {
      if (layer.id == _selectedId) return layer;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _document = PhotoDocument.fromJson(widget.initialData ?? {});
    _history = PhotoHistory(_document);
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialData != null) {
      _editVersion = 1;
      _saveTimer = Timer(
        const Duration(milliseconds: 900),
        () => unawaited(_save()),
      );
    }
    _requestMedia();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && _editVersion != _savedVersion) {
      unawaited(_save());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _composition?.dispose();
    _previewCache.dispose();
    _canvasFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _change(VoidCallback change, {bool media = false, bool commit = true}) {
    setState(change);
    if (commit) {
      _commit();
    } else {
      _saveTimer?.cancel();
    }
    if (media) _requestMedia();
  }

  void _commit() {
    if (!mounted) return;
    _history.commit(_document);
    _editVersion++;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_save()),
    );
    setState(() {});
  }

  void _requestMedia() {
    final key = _previewCache.mediaKey(_document);
    if (key == _mediaKey) return;
    _mediaKey = key;
    _revision++;
    _pendingMedia = true;
    if (!_loadingMedia) unawaited(_loadMedia());
  }

  Future<void> _loadMedia() async {
    if (!mounted) return;
    setState(() => _loadingMedia = true);
    while (_pendingMedia && mounted) {
      _pendingMedia = false;
      final revision = _revision;
      try {
        final next = await _previewCache.prepare(_document.clone());
        if (!mounted || revision != _revision) {
          next.dispose();
          continue;
        }
        final previous = _composition;
        setState(() {
          _composition = next;
          _error = null;
        });
        previous?.dispose();
      } catch (error) {
        if (mounted && revision == _revision) {
          setState(() {
            _mediaKey = null;
            _error = error.toString();
          });
        }
      }
    }
    if (mounted) setState(() => _loadingMedia = false);
  }

  Future<void> _save({bool feedback = false}) async {
    if (_saveFuture != null) {
      await _saveFuture;
      return;
    }
    _saveTimer?.cancel();
    final future = _saveImpl(feedback);
    _saveFuture = future;
    await future;
    _saveFuture = null;
  }

  Future<void> _saveImpl(bool feedback) async {
    if (mounted) setState(() => _saving = true);
    try {
      do {
        final version = _editVersion;
        await widget.onSave(_document.toJson(), _document.title, null);
        _savedVersion = version;
      } while (mounted && _savedVersion != _editVersion);
      if (feedback) _message('Project saved on this device.');
    } catch (error) {
      _message('Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_editVersion != _savedVersion) await _save();
    if (!mounted || _editVersion != _savedVersion) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _import({
    bool background = false,
    bool overlay = false,
    PhotoLayer? replaceLayer,
  }) async {
    if (overlay && !_canAddLayer()) return;
    await _run(() async {
      final path = await widget.pickImage();
      if (path == null || !mounted) return;
      if (replaceLayer != null) {
        replaceLayer.path = path;
      } else if (background) {
        _document.backgroundPath = path;
      } else if (overlay) {
        final layer = PhotoLayer(
          id: _id(),
          kind: 'image',
          path: path,
          x: .2,
          y: .2,
          width: .6,
          height: .6,
        );
        _document.layers.add(layer);
        _selectedId = layer.id;
        _tool = 'Layers';
      } else {
        final buffer = await ui.ImmutableBuffer.fromFilePath(path);
        ui.ImageDescriptor? descriptor;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          if (descriptor.width * descriptor.height > 32000000) {
            throw const FormatException(
              'Use a photo of 32 megapixels or smaller.',
            );
          }
          if (_document.layers.isEmpty && _document.imagePath == null) {
            final scale = math.min(
              1.0,
              4096 / math.max(descriptor.width, descriptor.height),
            );
            _document.width = math.max(64, (descriptor.width * scale).round());
            _document.height = math.max(
              64,
              (descriptor.height * scale).round(),
            );
          }
        } finally {
          descriptor?.dispose();
          buffer.dispose();
        }
        if (!mounted) return;
        _document.imagePath = path;
        _document.rotation = 0;
        _document.flipHorizontal = false;
        _document.cropLeft = _document.cropTop = 0;
        _document.cropRight = _document.cropBottom = 1;
      }
      _commit();
      _requestMedia();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeBackground() async {
    if (_document.imagePath == null) {
      _message('Import a photo first.');
      return;
    }
    await _run(() async {
      final path = await widget.removeBackground(_document.imagePath!);
      if (!mounted) return;
      _document.imagePath = path;
      _document.backgroundColor = 0x00000000;
      _commit();
      _requestMedia();
      _message(
        'Background removed on your device. Pick a color or image to replace it.',
      );
    });
  }

  Future<void> _export() async {
    final export = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export your photo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('PNG keeps layers crisp and preserves transparency.'),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.high_quality_outlined),
                title: const Text('High resolution PNG'),
                subtitle: Text(
                  '${_document.width} × ${_document.height} · up to 4096 px',
                ),
                onTap: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (export != true || !mounted) return;
    await _run(() async {
      await _save();
      final bytes = await exportPhoto(_document.clone());
      final location = await widget.exportBytes(
        bytes,
        'FrameLab_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      _message('PNG exported: $location');
    });
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();

  bool _canAddLayer() {
    if (_document.layers.length < PhotoDocument.maxLayers) return true;
    _message(
      'This canvas has 48 layers. Remove a layer before adding another.',
    );
    return false;
  }

  Future<void> _text({PhotoLayer? layer, bool title = false}) async {
    if (!title && layer == null && !_canAddLayer()) return;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _TextEditorDialog(
        initialText: title ? _document.title : layer?.text ?? 'Your story',
        isProjectTitle: title,
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    _change(() {
      if (title) {
        _document.title = value;
      } else if (layer != null) {
        layer.text = value;
      } else {
        final newLayer = PhotoLayer(
          id: _id(),
          text: value,
          fontFamily: 'StudioSans',
        );
        _document.layers.add(newLayer);
        _selectedId = newLayer.id;
      }
    });
  }

  Future<void> _resize() async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => _CanvasSizeDialog(
        initialWidth: _document.width,
        initialHeight: _document.height,
      ),
    );
    if (result != null && mounted) {
      _change(() {
        _document.width = result.$1;
        _document.height = result.$2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 400;
    return PopScope(
      canPop: _allowExit || (!_busy && _editVersion == _savedVersion),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextButton(
            onPressed: _busy ? null : () => _text(title: true),
            child: Text(
              _document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Save project',
              onPressed: _busy ? null : () => _save(feedback: true),
              icon: const Icon(Icons.save_outlined),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _busy ? null : _export,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(narrow ? 'Export' : 'Export PNG'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape =
                  constraints.maxHeight < 420 && constraints.maxWidth > 600;
              final canvas = _buildCanvas();
              final controls = _buildControls(
                landscape ? 240 : math.min(224, constraints.maxHeight * .36),
              );
              if (landscape) {
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _topBar(),
                          Expanded(child: canvas),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 340,
                      child: Column(
                        children: [
                          Expanded(child: controls),
                          _toolbar(),
                        ],
                      ),
                    ),
                  ],
                );
              }
              final largeText = MediaQuery.textScalerOf(context).scale(16) > 25;
              if (largeText) {
                // Give large accessibility text a scrollable portrait layout.
                // The canvas receives a bounded height because it contains an
                // internal Expanded widget.
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _topBar(),
                      SizedBox(
                        height: math.max(280, constraints.maxWidth * .82),
                        child: canvas,
                      ),
                      controls,
                      _toolbar(),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  _topBar(),
                  Expanded(child: canvas),
                  controls,
                  _toolbar(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Undo',
          onPressed: !_busy && _history.canUndo
              ? () => _restore(undo: true)
              : null,
          icon: const Icon(Icons.undo_rounded),
        ),
        IconButton(
          tooltip: 'Redo',
          onPressed: !_busy && _history.canRedo
              ? () => _restore(undo: false)
              : null,
          icon: const Icon(Icons.redo_rounded),
        ),
        Expanded(
          child: Text(
            _saving
                ? 'Saving…'
                : _editVersion == _savedVersion
                ? 'On device'
                : 'Unsaved',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _busy ? null : () => _import(),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Photo'),
        ),
      ],
    ),
  );

  void _restore({required bool undo}) {
    setState(() {
      _document = undo ? _history.undo() : _history.redo();
      _selectedId = null;
      _editVersion++;
    });
    _requestMedia();
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_save()),
    );
  }

  Widget _buildCanvas() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _document.width / _document.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _canvasSize = constraints.biggest;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(painter: _CheckerPainter()),
                      Semantics(
                        label:
                            'Photo canvas. Select layers below to move and resize them.',
                        image: true,
                        child: Focus(
                          focusNode: _canvasFocus,
                          autofocus: true,
                          onKeyEvent: _canvasKey,
                          child: GestureDetector(
                            onTapDown: (details) =>
                                _selectAt(details.localPosition),
                            onPanStart: (details) =>
                                _selectAt(details.localPosition),
                            onPanUpdate: (details) {
                              if (_selected == null ||
                                  _busy ||
                                  _canvasSize.isEmpty) {
                                return;
                              }
                              _change(() {
                                _selected!.x =
                                    (_selected!.x +
                                            details.delta.dx /
                                                _canvasSize.width)
                                        .clamp(-.8, .95);
                                _selected!.y =
                                    (_selected!.y +
                                            details.delta.dy /
                                                _canvasSize.height)
                                        .clamp(-.8, .95);
                              }, commit: false);
                            },
                            onPanEnd: (_) {
                              if (_selected != null) _commit();
                            },
                            onDoubleTapDown: (details) =>
                                _selectAt(details.localPosition),
                            onDoubleTap: () {
                              if (_selected?.kind == 'text') {
                                unawaited(_text(layer: _selected));
                              }
                            },
                            child: RepaintBoundary(
                              child: CustomPaint(
                                key: const ValueKey('photo-live-preview'),
                                painter: PhotoPainter(
                                  composition: _composition,
                                  document: _document,
                                  selectedId: _selectedId,
                                  showGrid: _tool == 'Crop',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_document.imagePath == null &&
                          _document.layers.isEmpty)
                        Center(
                          child: FilledButton.tonalIcon(
                            onPressed: _busy ? null : () => _import(),
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: const Text('Import a photo'),
                          ),
                        ),
                      if (_busy)
                        const ColoredBox(
                          color: Color(0x88000000),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Processing on your device…'),
                              ],
                            ),
                          ),
                        ),
                      if (_loadingMedia && !_busy)
                        const Align(
                          alignment: Alignment.topCenter,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Text(
            _error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          )
        else
          Text(
            '${_document.width} × ${_document.height}  ·  ${_selected != null ? 'Drag to move · Layers for controls' : 'Offline canvas'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );

  void _selectAt(Offset point) {
    if (_busy) return;
    String? id;
    for (final layer in _document.layers.reversed) {
      final rect = Rect.fromLTWH(
        layer.x * _canvasSize.width,
        layer.y * _canvasSize.height,
        layer.width * _canvasSize.width,
        layer.height * _canvasSize.height,
      );
      final delta = point - rect.center;
      final local =
          rect.center +
          Offset(
            delta.dx * math.cos(layer.rotation) +
                delta.dy * math.sin(layer.rotation),
            -delta.dx * math.sin(layer.rotation) +
                delta.dy * math.cos(layer.rotation),
          );
      if (rect.inflate(12).contains(local)) {
        id = layer.id;
        break;
      }
    }
    setState(() => _selectedId = id);
    _canvasFocus.requestFocus();
  }

  KeyEventResult _canvasKey(FocusNode node, KeyEvent event) {
    if (_busy || event is KeyUpEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      final undo = !HardwareKeyboard.instance.isShiftPressed;
      if (undo ? _history.canUndo : _history.canRedo) _restore(undo: undo);
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (_selected == null ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final moved = _moveSelected(
      key,
      distance: HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0,
    );
    return moved ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  bool _moveSelected(LogicalKeyboardKey key, {double distance = 1}) {
    final layer = _selected;
    if (layer == null) return false;
    final step = switch (key) {
      LogicalKeyboardKey.arrowLeft => Offset(-distance / _document.width, 0),
      LogicalKeyboardKey.arrowRight => Offset(distance / _document.width, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -distance / _document.height),
      LogicalKeyboardKey.arrowDown => Offset(0, distance / _document.height),
      _ => Offset.zero,
    };
    if (step == Offset.zero) return false;
    _change(() {
      layer.x = (layer.x + step.dx).clamp(-.8, .95);
      layer.y = (layer.y + step.dy).clamp(-.8, .95);
    });
    return true;
  }

  Widget _toolbar() => Material(
    color: AppColors.surface,
    child: SizedBox(
      height: math.max(76, 48 + MediaQuery.textScalerOf(context).scale(28)),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _tools.length,
        separatorBuilder: (_, index) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final item = _tools[index];
          final selected = item.$1 == _tool;
          return Semantics(
            selected: selected,
            child: InkWell(
              onTap: _busy ? null : () => setState(() => _tool = item.$1),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: math.max(76, MediaQuery.textScalerOf(context).scale(72)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.$2,
                      color: selected ? AppColors.primary : AppColors.muted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.$1,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? AppColors.primary : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _buildControls(double height) => Container(
    height: height,
    width: double.infinity,
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: AbsorbPointer(
      absorbing: _busy,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: switch (_tool) {
          'Adjust' => _adjustments(),
          'Crop' => _crop(),
          'Filters' => _filters(),
          'Text' => _textTools(),
          'Stickers' => _stickers(),
          'Background' => _background(),
          'Layout' => _layout(),
          _ => _layers(),
        },
      ),
    ),
  );

  Widget _heading(String title, [String? description]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      if (description != null)
        Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 8),
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> setter,
  ) => Row(
    children: [
      SizedBox(
        width: math.min(128, MediaQuery.textScalerOf(context).scale(84)),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.text),
        ),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          label: value.toStringAsFixed(2),
          key: ValueKey('photo-slider-$label'),
          onChanged: (value) => _change(() => setter(value), commit: false),
          onChangeEnd: (_) => _commit(),
        ),
      ),
      SizedBox(
        width: 34,
        child: Text(
          value.toStringAsFixed(1),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  Widget _adjustments() => Column(
    children: [
      _heading('Adjust', 'Live preview · original photo stays unchanged.'),
      _slider(
        'Brightness',
        _document.brightness,
        0,
        2,
        (v) => _document.brightness = v,
      ),
      _slider(
        'Contrast',
        _document.contrast,
        0,
        2,
        (v) => _document.contrast = v,
      ),
      _slider(
        'Saturation',
        _document.saturation,
        0,
        2,
        (v) => _document.saturation = v,
      ),
      _slider(
        'Exposure',
        _document.exposure,
        -2,
        2,
        (v) => _document.exposure = v,
      ),
      _slider('Blur', _document.blur, 0, 30, (v) => _document.blur = v),
    ],
  );

  Widget _crop() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Frame the moment',
        'Crop edges adjust the source; Layout changes output proportions.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.rotate_right),
            label: const Text('Rotate 90°'),
            onPressed: () => _change(() {
              _document.rotation = (_document.rotation + 1) % 4;
              final width = _document.width;
              _document.width = _document.height;
              _document.height = width;
              _document.cropLeft = _document.cropTop = 0;
              _document.cropRight = _document.cropBottom = 1;
            }),
          ),
          ActionChip(
            avatar: const Icon(Icons.flip),
            label: const Text('Flip'),
            onPressed: () => _change(
              () => _document.flipHorizontal = !_document.flipHorizontal,
            ),
          ),
          ActionChip(
            label: const Text('Reset crop'),
            onPressed: () => _change(() {
              _document.cropLeft = _document.cropTop = 0;
              _document.cropRight = _document.cropBottom = 1;
            }),
          ),
        ],
      ),
      _slider(
        'Left',
        _document.cropLeft,
        0,
        _document.cropRight - .05,
        (v) => _document.cropLeft = v,
      ),
      _slider(
        'Right',
        _document.cropRight,
        _document.cropLeft + .05,
        1,
        (v) => _document.cropRight = v,
      ),
      _slider(
        'Top',
        _document.cropTop,
        0,
        _document.cropBottom - .05,
        (v) => _document.cropTop = v,
      ),
      _slider(
        'Bottom',
        _document.cropBottom,
        _document.cropTop + .05,
        1,
        (v) => _document.cropBottom = v,
      ),
    ],
  );

  Widget _filters() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('A different feeling', 'Tap a look. Fine tune it in Adjust.'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ['Original', 'Noir', 'Warm', 'Cool', 'Fade', 'Vivid', 'Sepia']
            .map((name) {
              return ChoiceChip(
                selected: _document.filter == name,
                label: Text(name),
                onSelected: (_) async {
                  if (mounted) {
                    _change(() => _document.filter = name);
                  }
                },
              );
            })
            .toList(),
      ),
    ],
  );

  Widget _textTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: _heading('Words that stand out')),
          FilledButton.icon(
            onPressed: () => _text(),
            icon: const Icon(Icons.add),
            label: const Text('Add text'),
          ),
        ],
      ),
      if (_selected?.kind == 'text') ...[
        TextButton.icon(
          onPressed: () => _text(layer: _selected),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit selected text'),
        ),
        _layerOptions(_selected!),
      ] else
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Tap text on the canvas or select it in Layers to change its style.',
          ),
        ),
    ],
  );

  Widget _stickers() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Shapes & stickers',
        'Original vector elements, crisp at every size.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in <(String, IconData)>[
            ('rect', Icons.rectangle_outlined),
            ('circle', Icons.circle_outlined),
            ('star', Icons.star_outline_rounded),
            ('heart', Icons.favorite_outline),
          ])
            ActionChip(
              avatar: Icon(item.$2),
              label: Text(item.$1),
              onPressed: () async {
                if (!_canAddLayer()) return;
                if (!mounted) return;
                _change(() {
                  final layer = PhotoLayer(
                    id: _id(),
                    kind: item.$1,
                    x: .3,
                    y: .3,
                    width: .3,
                    height: .3,
                    color: 0xffd4ef89,
                  );
                  _document.layers.add(layer);
                  _selectedId = layer.id;
                  _tool = 'Layers';
                });
              },
            ),
          ActionChip(
            avatar: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Image overlay'),
            onPressed: () => _import(overlay: true),
          ),
        ],
      ),
    ],
  );

  Widget _background() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Change the scene',
        'Remove a portrait background on-device, then replace it.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.auto_fix_high),
            label: const Text('Remove background'),
            onPressed: _removeBackground,
          ),
          ActionChip(
            avatar: const Icon(Icons.image_outlined),
            label: const Text('Background image'),
            onPressed: () => _import(background: true),
          ),
          if (_document.backgroundPath != null)
            ActionChip(
              label: const Text('Clear background image'),
              onPressed: () =>
                  _change(() => _document.backgroundPath = null, media: true),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _colorPicker(
        _document.backgroundColor,
        (color) => _change(() => _document.backgroundColor = color),
      ),
    ],
  );

  Widget _layout() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Made for your next post',
        'Media fills the canvas without stretching. Layers remain editable.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in <(String, int, int)>[
            ('Post 1:1', 1080, 1080),
            ('Story / Reel', 1080, 1920),
            ('Portrait 4:5', 1080, 1350),
            ('YouTube', 1280, 720),
            ('Landscape', 1920, 1080),
            ('Poster', 1600, 2000),
          ])
            ActionChip(
              label: Text(preset.$1),
              onPressed: () => _change(() {
                _document.width = preset.$2;
                _document.height = preset.$3;
              }),
            ),
          ActionChip(
            avatar: const Icon(Icons.open_in_full),
            label: const Text('Custom size'),
            onPressed: _resize,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Fill canvas'),
            selected: _document.imageFit == 'cover',
            onSelected: (_) => _change(() => _document.imageFit = 'cover'),
          ),
          ChoiceChip(
            label: const Text('Fit whole photo'),
            selected: _document.imageFit == 'contain',
            onSelected: (_) => _change(() => _document.imageFit = 'contain'),
          ),
        ],
      ),
    ],
  );

  Widget _layers() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Every element, editable',
        'Select a layer; use sliders or drag it on the canvas.',
      ),
      if (_document.layers.isEmpty)
        const Text('Add text, shapes or image overlays to start.'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _document.layers.reversed
            .map(
              (layer) => ChoiceChip(
                selected: layer.id == _selectedId,
                label: Text(
                  layer.kind == 'text' ? layer.text : layer.kind,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onSelected: (_) => setState(() => _selectedId = layer.id),
              ),
            )
            .toList(),
      ),
      if (_selected != null) ...[
        Row(
          children: [
            if (_selected!.kind == 'text')
              IconButton(
                tooltip: 'Edit text',
                onPressed: () => _text(layer: _selected),
                icon: const Icon(Icons.edit_outlined),
              ),
            IconButton(
              tooltip: 'Bring forward',
              onPressed: () => _reorderLayer(1),
              icon: const Icon(Icons.flip_to_front),
            ),
            IconButton(
              tooltip: 'Send backward',
              onPressed: () => _reorderLayer(-1),
              icon: const Icon(Icons.flip_to_back),
            ),
            IconButton(
              tooltip: 'Duplicate layer',
              onPressed: () => _change(() {
                if (!_canAddLayer()) return;
                final copy = PhotoLayer.fromJson(_selected!.toJson())
                  ..id = _id();
                copy.x += .03;
                copy.y += .03;
                _document.layers.add(copy);
                _selectedId = copy.id;
              }),
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              tooltip: 'Delete layer',
              onPressed: () => _change(() {
                _document.layers.removeWhere(
                  (layer) => layer.id == _selectedId,
                );
                _selectedId = null;
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (_selected!.kind == 'image')
          TextButton.icon(
            onPressed: () => _import(replaceLayer: _selected),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Replace layer image'),
          ),
        _layerOptions(_selected!),
      ],
    ],
  );

  void _reorderLayer(int delta) {
    final layer = _selected;
    if (layer == null) return;
    final index = _document.layers.indexOf(layer);
    final next = (index + delta).clamp(0, _document.layers.length - 1);
    _change(() {
      _document.layers.removeAt(index);
      _document.layers.insert(next, layer);
    });
  }

  Widget _layerOptions(PhotoLayer layer) => Column(
    children: [
      if (layer.kind != 'image')
        _colorPicker(
          layer.color,
          (color) => _change(() => layer.color = color),
        ),
      if (layer.kind == 'text') ...[
        _slider(
          'Text size',
          layer.fontSize,
          .01,
          .4,
          (value) => layer.fontSize = value,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final font in <(String, String, bool)>[
              ('Sans', 'StudioSans', false),
              ('Serif', 'StudioSerif', false),
              ('Mono', 'StudioMono', false),
              ('Script', 'StudioScript', true),
              ('Display', 'StudioDisplay', true),
            ])
              ChoiceChip(
                label: Text(font.$1),
                selected: layer.fontFamily == font.$2,
                onSelected: (_) async {
                  if (mounted) _change(() => layer.fontFamily = font.$2);
                },
              ),
            FilterChip(
              label: const Text('Bold'),
              selected: layer.bold,
              onSelected: (value) => _change(() => layer.bold = value),
            ),
          ],
        ),
      ],
      _slider('Horizontal', layer.x, -.8, .95, (v) => layer.x = v),
      _slider('Vertical', layer.y, -.8, .95, (v) => layer.y = v),
      _slider('Width', layer.width, .02, 1.5, (v) => layer.width = v),
      _slider('Height', layer.height, .02, 1.5, (v) => layer.height = v),
      _slider(
        'Rotation',
        layer.rotation,
        -math.pi,
        math.pi,
        (v) => layer.rotation = v,
      ),
      _slider('Opacity', layer.opacity, 0, 1, (v) => layer.opacity = v),
    ],
  );

  Widget _colorPicker(int selected, ValueChanged<int> onChanged) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: _colors
        .map(
          (color) => Semantics(
            label: color == 0
                ? 'Transparent'
                : 'Color ${color.toRadixString(16)}',
            selected: color == selected,
            button: true,
            child: InkWell(
              onTap: () => onChanged(color),
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected == color
                            ? AppColors.primary
                            : AppColors.muted,
                        width: selected == color ? 3 : 1,
                      ),
                    ),
                    child: color == 0
                        ? const Icon(Icons.block, size: 20)
                        : selected == color
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: Color(color).computeLuminance() > .5
                                ? Colors.black
                                : Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(),
  );
}

class _TextEditorDialog extends StatefulWidget {
  const _TextEditorDialog({
    required this.initialText,
    required this.isProjectTitle,
  });

  final String initialText;
  final bool isProjectTitle;

  @override
  State<_TextEditorDialog> createState() => _TextEditorDialogState();
}

class _TextEditorDialogState extends State<_TextEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isProjectTitle ? 'Project name' : 'Edit text'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.isProjectTitle ? 80 : 500,
      minLines: widget.isProjectTitle ? 1 : 2,
      maxLines: widget.isProjectTitle ? 1 : 5,
      decoration: InputDecoration(
        labelText: widget.isProjectTitle ? 'Name' : 'Text',
        border: const OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Apply'),
      ),
    ],
  );
}

class _CanvasSizeDialog extends StatefulWidget {
  const _CanvasSizeDialog({
    required this.initialWidth,
    required this.initialHeight,
  });

  final int initialWidth;
  final int initialHeight;

  @override
  State<_CanvasSizeDialog> createState() => _CanvasSizeDialogState();
}

class _CanvasSizeDialogState extends State<_CanvasSizeDialog> {
  late final TextEditingController _width = TextEditingController(
    text: '${widget.initialWidth}',
  );
  late final TextEditingController _height = TextEditingController(
    text: '${widget.initialHeight}',
  );
  String? _error;

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _resize() {
    final width = int.tryParse(_width.text);
    final height = int.tryParse(_height.text);
    if (width == null ||
        height == null ||
        width < 64 ||
        width > 4096 ||
        height < 64 ||
        height > 4096) {
      setState(() => _error = 'Enter dimensions from 64 to 4096.');
      return;
    }
    Navigator.pop(context, (width, height));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Resize canvas'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _width,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Width in pixels'),
          ),
          TextField(
            controller: _height,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Height in pixels'),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 12),
          const Text('64–4096 px. Export preserves the full canvas size.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _resize, child: const Text('Resize')),
    ],
  );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var y = 0; y < size.height; y += 16) {
      for (var x = 0; x < size.width; x += 16) {
        paint.color = ((x ~/ 16 + y ~/ 16).isEven)
            ? const Color(0xff242630)
            : const Color(0xff30323d);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 16, 16),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
