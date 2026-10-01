import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../photo_editor/domain/background_brush.dart';
import '../../photo_editor/data/background_refine_renderer.dart';
import '../../photo_editor/presentation/background_refine_screen.dart';
import '../data/ffmpeg_video_renderer.dart';
import '../data/video_cutout_service.dart';
import '../domain/video_document.dart';

/// Explicit processing workflow; ordinary canvas edits never enter this route.
class VideoCutoutScreen extends StatefulWidget {
  const VideoCutoutScreen({
    super.key,
    required this.clip,
    required this.pickImage,
  });
  final VideoClip clip;
  final Future<String?> Function() pickImage;
  @override
  State<VideoCutoutScreen> createState() => _VideoCutoutScreenState();
}

class _VideoCutoutScreenState extends State<VideoCutoutScreen>
    with WidgetsBindingObserver {
  final _service = VideoCutoutService();
  String? _frame, _autoFrame, _refinedFrame, _backgroundPath;
  List<BackgroundBrushStroke> _strokes = [];
  bool _automatic = true;
  bool _loading = true;
  bool _processing = false;
  bool _closing = false;
  double _progress = 0;
  int _color = 0xff000000;
  String _stage = 'Reading a preview frame';
  String? _error;

  VideoClip get _sourceClip => VideoCutoutService.originalFor(widget.clip);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final recipe = widget.clip.cutoutRecipe;
    if (recipe != null) {
      _automatic = recipe['automatic'] != false;
      _color = (recipe['backgroundColor'] as num?)?.toInt() ?? _color;
      _backgroundPath = recipe['backgroundPath'] as String?;
      _strokes = (recipe['strokes'] as List? ?? [])
          .map(
            (item) => BackgroundBrushStroke.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    }
    unawaited(_loadFrame());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && (_processing || _loading)) {
      unawaited(_service.cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _loadFrame() async {
    _service.resetForRetry();
    try {
      final frame = _frame ?? await _service.previewFrame(_sourceClip);
      if (!mounted) return;
      setState(() {
        _frame = frame;
        _stage = 'Removing preview background on-device';
      });
      final auto = _automatic
          ? (_autoFrame ?? await _service.autoPreview(frame))
          : null;
      String? refined;
      if (_strokes.isNotEmpty) {
        final source = await BackgroundRefineSource.load(
          frame,
          initialMaskPath: auto,
        );
        try {
          refined = await saveRefinedBackground(
            originalPath: frame,
            initialMaskPath: auto,
            outputSize: source.outputSize,
            strokes: _strokes,
          );
        } finally {
          source.dispose();
        }
      }
      if (mounted) {
        setState(() {
          if (auto != null) _autoFrame = auto;
          _refinedFrame = refined;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _manual() async {
    if (_frame == null || _processing || _loading || _closing) return;
    List<BackgroundBrushStroke> strokes = [];
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BackgroundRefineScreen(
          originalPath: _frame!,
          initialMaskPath: _automatic ? _autoFrame : null,
          initialStrokes: _strokes,
          onApplied: (value) => strokes = value,
        ),
      ),
    );
    if (path != null && mounted) {
      setState(() {
        _strokes = strokes;
        _refinedFrame = path;
        _error = null;
      });
    }
  }

  Future<void> _apply() async {
    if (_processing || _loading || _closing) return;
    _service.resetForRetry();
    setState(() {
      _processing = true;
      _error = null;
      _progress = 0;
    });
    try {
      final path = await _service.process(
        _sourceClip,
        automatic: _automatic,
        backgroundColor: _color,
        backgroundPath: _backgroundPath,
        strokes: _strokes.map((stroke) => stroke.toMap()).toList(),
        onProgress: (value, stage) {
          if (mounted && !_closing) {
            setState(() {
              _progress = value;
              _stage = stage;
            });
          }
        },
      );
      final renderer = FfmpegVideoRenderer();
      VideoClip processed;
      try {
        processed = await renderer.probe(path);
      } finally {
        await renderer.dispose();
      }
      if (!mounted || _closing) return;
      setState(() => _processing = false);
      Navigator.of(context).pop(
        widget.clip.copyWith(
          path: path,
          start: 0,
          end: math.min(
            processed.sourceDuration,
            _sourceClip.end - _sourceClip.start,
          ),
          sourceDuration: processed.sourceDuration,
          width: processed.width,
          height: processed.height,
          hasAudio: processed.hasAudio,
          cutoutOriginal: _sourceClip,
          cutoutRecipe: {
            'automatic': _automatic,
            'backgroundColor': _color,
            'backgroundPath': _backgroundPath,
            'strokes': _strokes.map((stroke) => stroke.toMap()).toList(),
          },
        ),
      );
    } catch (e) {
      if (mounted && !_closing) {
        setState(() {
          _processing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    await _service.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final image = _refinedFrame ?? (_automatic ? _autoFrame : _frame) ?? _frame;
    return PopScope(
      canPop: _closing || (!_processing && !_loading),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cancel cutout',
            onPressed: _close,
            icon: const Icon(Icons.close),
          ),
          title: const Text('Video cutout'),
          actions: [
            TextButton(
              onPressed: _loading || _processing || _closing ? null : _apply,
              child: const Text('Apply'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio:
                          widget.clip.width / math.max(1, widget.clip.height),
                      child: ClipRect(
                        child: Container(
                          color: Color(_color),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_backgroundPath != null)
                                Image.file(
                                  File(_backgroundPath!),
                                  fit: BoxFit.cover,
                                ),
                              if (image != null)
                                Image.file(
                                  File(image),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Text('Preview unavailable'),
                                  ),
                                ),
                              if (_loading)
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                flex: 0,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .48,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_processing || _loading) ...[
                          Text(
                            _stage,
                            style: const TextStyle(color: AppColors.text),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _loading ? null : _progress,
                          ),
                          if (_processing)
                            Text('${(_progress * 100).round()}%'),
                          const SizedBox(height: 12),
                        ],
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                        if (_error != null && !_processing && !_loading)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              unawaited(_loadFrame());
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry preview'),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Automatic'),
                              selected: _automatic,
                              onSelected: _loading || _processing
                                  ? null
                                  : (_) => setState(() {
                                      _automatic = true;
                                      _refinedFrame = null;
                                      _loading = true;
                                      unawaited(_loadFrame());
                                    }),
                            ),
                            ChoiceChip(
                              label: const Text('Manual only'),
                              selected: !_automatic,
                              onSelected: _loading || _processing
                                  ? null
                                  : (_) => setState(() {
                                      _automatic = false;
                                      _refinedFrame = null;
                                      _loading = true;
                                      unawaited(_loadFrame());
                                    }),
                            ),
                            OutlinedButton.icon(
                              onPressed: _loading || _processing
                                  ? null
                                  : _manual,
                              icon: const Icon(Icons.brush_outlined),
                              label: const Text('Erase / Restore'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Replacement background',
                          style: TextStyle(color: AppColors.text),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final color in [
                              0xff000000,
                              0xffffffff,
                              0xff18181c,
                              0xff386d57,
                              0xffa9d7e4,
                              0xfffca98d,
                            ])
                              Semantics(
                                label:
                                    'Background color ${color.toRadixString(16)}',
                                button: true,
                                selected:
                                    _backgroundPath == null && color == _color,
                                child: InkWell(
                                  onTap: _loading || _processing
                                      ? null
                                      : () => setState(() {
                                          _color = color;
                                          _backgroundPath = null;
                                        }),
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Color(color),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            _backgroundPath == null &&
                                                color == _color
                                            ? AppColors.primary
                                            : AppColors.border,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: _loading || _processing
                                  ? null
                                  : () async {
                                      final path = await widget.pickImage();
                                      if (mounted && path != null) {
                                        setState(() => _backgroundPath = path);
                                      }
                                    },
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Image'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Automatic removal follows the subject in every frame. Manual brush corrections stay in the same image area across this trimmed clip; they do not track motion.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Runs offline. Detailed hair, fast motion and complex backgrounds may need refinement. Output: up to 1920 px, 30 fps, with original audio.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
