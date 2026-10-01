import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/filter_strip.dart';
import '../data/ffmpeg_video_renderer.dart';
import '../domain/video_document.dart';
import '../domain/video_history.dart';
import '../domain/video_renderer.dart';
import '../domain/video_realtime_preview.dart';

/// The editor knows recipes and rendering. Storage, picking and
/// publishing are injected by the application composition root.
class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({
    super.key,
    this.initialData,
    required this.onSave,
    required this.pickVideos,
    required this.pickAudio,
    required this.pickImage,
    required this.publishVideo,
    this.renderer,
    this.playerFactory,
    this.thumbnailLoader,
    this.refineImageBackground,
    this.removeVideoBackground,
  });
  final Map<String, dynamic>? initialData;
  final Future<void> Function(
    Map<String, dynamic>,
    String title,
    String? thumbnailPath,
  )
  onSave;
  final Future<List<String>> Function() pickVideos;
  final Future<String?> Function() pickAudio;
  final Future<String?> Function() pickImage;
  final Future<String> Function(String renderedPath, String fileName)
  publishVideo;
  final VideoRenderer? renderer;

  /// Injectable playback boundary for tests; production opens the source file.
  final VideoPlayerController Function(String path)? playerFactory;
  final Future<String?> Function(String path, double timeSeconds)?
  thumbnailLoader;

  /// Explicit offline processing; canvas gestures never invoke these jobs.
  final Future<String?> Function(String originalPath, String? initialMaskPath)?
  refineImageBackground;
  final Future<VideoClip?> Function(VideoClip clip)? removeVideoBackground;

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen>
    with WidgetsBindingObserver {
  late VideoDocument _document;
  late VideoHistory _history;
  late VideoRenderer _renderer;
  VideoPlayerController? _player;
  String? _previewPath;
  String? _error;
  String _tool = 'Trim';
  bool _panelOpen = true;
  String _canvasTarget = 'clip';
  final _canvasKey = GlobalKey();
  final _layerKeys = <String, GlobalKey>{};
  final _overlayRatios = <String, Future<double>>{};
  String? _gestureTarget;
  final _canvasPointerOrigins = <int, Offset>{};
  final _canvasPointerPositions = <int, Offset>{};
  bool _gestureSessionActive = false;
  Offset _gestureFocal = Offset.zero;
  Offset _gestureCenter = Offset.zero;
  Offset _gestureCanvasFocal = Offset.zero;
  Size _gestureFrame = Size.zero;
  VideoClip? _gestureClip;
  VideoOverlay? _gestureOverlay;
  VideoText? _gestureText;
  bool _gestureChanged = false;
  bool _snapX = false;
  bool _snapY = false;
  bool _processingCutout = false;
  String _stage = 'Preparing export';
  int _selected = 0;
  int _revision = 0;
  int _previewRevision = -1;
  int _savedRevision = 0;
  double _progress = 0;
  double _splitFraction = .5;
  bool _loadingSource = false;
  bool _composedPreview = false;
  bool _wantsPlayback = false;
  bool _scrubbing = false;
  bool _advancing = false;
  bool _seekBusy = false;
  int _sourceGeneration = 0;
  String? _sourcePath;
  String? _openingPath;
  Future<void>? _openingSource;
  double? _pendingSeek;
  double? _appliedSpeed;
  double? _appliedVolume;
  final _position = ValueNotifier<double>(0);
  Timer? _seekTimer;
  final _thumbnails = <String, Future<String?>>{};
  final _thumbnailAnchors = <String, (double, double)>{};
  bool _importing = false;
  bool _rendering = false;
  bool _exporting = false;
  bool _exportCancelled = false;
  bool _saving = false;
  bool _allowExit = false;
  bool _suspended = false;
  Timer? _saveTimer;
  Future<void>? _job;
  Future<void>? _saveFuture;

  static const _tools = <(String, IconData)>[
    ('Trim', Icons.content_cut_rounded),
    ('Canvas', Icons.crop_rounded),
    ('Cutout', Icons.person_outline_rounded),
    ('Speed', Icons.speed_rounded),
    ('Audio', Icons.music_note_rounded),
    ('Text', Icons.text_fields_rounded),
    ('Adjust', Icons.tune_rounded),
    ('Filters', Icons.filter_vintage_outlined),
    ('Effects', Icons.auto_awesome_outlined),
    ('Transition', Icons.compare_arrows_rounded),
    ('Overlay', Icons.layers_outlined),
  ];
  static const _colors = [
    0xffffffff,
    0xffb4a0ff,
    0xffd4ef89,
    0xffffcf5c,
    0xfffca98d,
    0xff101116,
  ];

  VideoClip? get _clip => _document.clips.isEmpty
      ? null
      : _document.clips[_selected.clamp(0, _document.clips.length - 1)];
  VideoOverlay? get _activeOverlay =>
      _document.overlays
          .where((layer) => 'overlay:${layer.id}' == _canvasTarget)
          .firstOrNull ??
      _document.overlay;
  String _id() => DateTime.now().microsecondsSinceEpoch.toString();
  String _time(double value) =>
      '${(value / 60).floor().toString().padLeft(2, '0')}:${(value % 60).toStringAsFixed(1).padLeft(4, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _renderer = widget.renderer ?? FfmpegVideoRenderer();
    try {
      _document = widget.initialData == null
          ? VideoDocument()
          : VideoDocument.fromJson(widget.initialData!);
    } catch (_) {
      _document = VideoDocument();
      _error =
          'This video project could not be opened. Your saved file has not been changed.';
    }
    _history = VideoHistory(_document);
    if (_document.clips.isNotEmpty) _schedulePreview();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _suspended = state != AppLifecycleState.resumed;
    if (_suspended) {
      _wantsPlayback = false;
      unawaited(_player?.pause());
      unawaited(_save());
      if (!_exporting) unawaited(_renderer.cancel());
    } else if (!_composedPreview) {
      _schedulePreview();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _seekTimer?.cancel();
    _saveTimer?.cancel();
    _sourceGeneration++;
    final player = _player;
    player?.removeListener(_playerChanged);
    _player = null;
    _position.dispose();
    unawaited(_disposeResources(player));
    super.dispose();
  }

  Future<void> _disposeResources(VideoPlayerController? player) async {
    await _renderer.cancel();
    await player?.dispose();
    await _job;
    await _renderer.dispose();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _change(
    VideoDocument document, {
    bool render = true,
    bool commit = true,
  }) {
    if (!mounted || _exporting) return;
    setState(() {
      if (!render && _previewRevision == _revision) _previewRevision++;
      if (render) _composedPreview = false;
      _document = document;
      if (_canvasTarget.startsWith('overlay:') &&
              !document.overlays.any(
                (layer) => 'overlay:${layer.id}' == _canvasTarget,
              ) ||
          _canvasTarget.startsWith('text:') &&
              !document.texts.any(
                (layer) => 'text:${layer.id}' == _canvasTarget,
              )) {
        _canvasTarget = 'clip';
      }
      _selected = _selected.clamp(0, math.max(0, document.clips.length - 1));
      _revision++;
      _error = null;
      if (commit) {
        _history.commit(document);
        _refreshThumbnailAnchors();
      }
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_save()),
    );
    if (document.clips.isEmpty) unawaited(_clearPreview());
    if (render) _schedulePreview();
  }

  Future<void> _clearPreview() async {
    final player = _player;
    final path = _previewPath;
    setState(() {
      _player = null;
      _previewPath = null;
    });
    player?.removeListener(_playerChanged);
    _sourcePath = null;
    _sourceGeneration++;
    await player?.dispose();
    if (path != null) await _renderer.release(path);
  }

  void _editClip(VideoClip clip, {bool commit = true}) {
    final clips = [..._document.clips];
    clips[_selected] = clip;
    _change(_document.copyWith(clips: clips), commit: commit);
  }

  void _refreshThumbnailAnchors() {
    final layerTargets = {
      ..._document.overlays.map((layer) => 'overlay:${layer.id}'),
      ..._document.texts.map((text) => 'text:${text.id}'),
    };
    _layerKeys.removeWhere((target, _) => !layerTargets.contains(target));
    final overlayPaths = _document.overlays.map((layer) => layer.path).toSet();
    _overlayRatios.removeWhere((path, _) => !overlayPaths.contains(path));
    final ids = _document.clips.map((clip) => clip.id).toSet();
    _thumbnailAnchors.removeWhere((id, _) => !ids.contains(id));
    for (final clip in _document.clips) {
      _thumbnailAnchors[clip.id] = (clip.start, clip.end);
    }
  }

  void _commitGesture() {
    _history.commit(_document);
    _refreshThumbnailAnchors();
    setState(() {});
  }

  void _undo(bool redo) {
    final next = redo ? _history.redo() : _history.undo();
    _change(next, commit: false);
    _refreshThumbnailAnchors();
  }

  Future<void> _save({bool announce = false}) async {
    if (_saving) {
      try {
        await _saveFuture;
      } catch (_) {
        return;
      }
      if (_savedRevision != _revision) await _save(announce: announce);
      return;
    }
    if (_savedRevision == _revision) return;
    _saveTimer?.cancel();
    final revision = _revision;
    final document = _document;
    _saving = true;
    if (mounted) setState(() {});
    final future = Future<void>.sync(
      () => widget.onSave(document.toJson(), document.title, null),
    );
    _saveFuture = future;
    try {
      await future;
      _savedRevision = revision;
      if (announce) _message('Project saved on this device');
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Project could not be saved. $error');
      }
    } finally {
      _saving = false;
      _saveFuture = null;
      if (mounted) setState(() {});
    }
  }

  // Recipe changes only update the texture, color matrix and canvas. Encoding
  // is reserved for explicit composition preview and final export.
  void _schedulePreview() {
    if (_rendering && !_exporting) unawaited(_renderer.cancel());
    if (_document.clips.isEmpty || _suspended || _exporting) return;
    unawaited(_syncSource());
  }

  VideoPlayerController _makePlayer(String path) =>
      widget.playerFactory?.call(path) ??
      VideoPlayerController.file(File(path));

  Future<void> _syncSource() async {
    final clip = _clip;
    if (clip == null) return;
    if (_openingPath == clip.path && _openingSource != null) {
      await _openingSource;
      if (!mounted) return;
      final current = _clip;
      if (current != null &&
          current.path == clip.path &&
          _sourcePath == current.path &&
          !_composedPreview &&
          !_exporting &&
          !_suspended &&
          _player != null &&
          _player!.value.isInitialized) {
        _applyPlaybackSettings(_player!, current);
      }
      return;
    }
    _openingPath = clip.path;
    final opening = _openSource();
    _openingSource = opening;
    try {
      await opening;
    } finally {
      if (identical(opening, _openingSource)) {
        _openingSource = null;
        _openingPath = null;
      }
    }
  }

  Future<void> _openSource() async {
    final clip = _clip;
    if (clip == null || !mounted || _suspended || _exporting) return;
    final existing = _player;
    if (_sourcePath == clip.path &&
        existing != null &&
        existing.value.isInitialized) {
      _applyPlaybackSettings(existing, clip);
      final seconds = existing.value.position.inMilliseconds / 1000;
      if (!_seekBusy &&
          !_scrubbing &&
          (seconds < clip.start || seconds > clip.end)) {
        _queueSeek(VideoPreviewPosition.startOf(_document, _selected));
      }
      _playerChanged();
      return;
    }
    final generation = ++_sourceGeneration;
    final next = _makePlayer(clip.path);
    setState(() => _loadingSource = true);
    try {
      await next.initialize();
      await next.setLooping(false);
      await next.setPlaybackSpeed(clip.speed);
      await next.setVolume(clip.volume.clamp(0, 1));
      await next.seekTo(Duration(milliseconds: (clip.start * 1000).round()));
      if (!mounted || generation != _sourceGeneration || _exporting) {
        await next.dispose();
        return;
      }
      final previous = _player;
      final previousPath = _previewPath;
      previous?.removeListener(_playerChanged);
      setState(() {
        _player = next;
        _sourcePath = clip.path;
        _previewPath = null;
        _composedPreview = false;
        _appliedSpeed = clip.speed;
        _appliedVolume = clip.volume.clamp(0, 1);
        _loadingSource = false;
      });
      next.addListener(_playerChanged);
      _playerChanged();
      await previous?.dispose();
      if (previousPath != null) await _renderer.release(previousPath);
      if (_wantsPlayback && !_scrubbing) await next.play();
    } catch (error) {
      await next.dispose();
      if (mounted && generation == _sourceGeneration) {
        setState(() {
          _loadingSource = false;
          _error =
              'This clip could not be played. Try another MP4 file. $error';
        });
      }
    }
  }

  void _applyPlaybackSettings(VideoPlayerController player, VideoClip clip) {
    if (_appliedSpeed != clip.speed) {
      _appliedSpeed = clip.speed;
      unawaited(player.setPlaybackSpeed(clip.speed));
    }
    final volume = clip.volume.clamp(0, 1).toDouble();
    if (_appliedVolume != volume) {
      _appliedVolume = volume;
      unawaited(player.setVolume(volume));
    }
  }

  void _playerChanged() {
    final player = _player;
    if (!mounted ||
        player == null ||
        !player.value.isInitialized ||
        _scrubbing ||
        _seekBusy) {
      return;
    }
    final seconds = player.value.position.inMilliseconds / 1000;
    if (_composedPreview) {
      _position.value = seconds.clamp(0, _document.duration);
      return;
    }
    final clip = _clip;
    if (clip == null) return;
    _position.value =
        (VideoPreviewPosition.startOf(_document, _selected) +
                (seconds - clip.start).clamp(0, clip.end - clip.start) /
                    clip.speed)
            .clamp(0, _document.duration);
    final playEnd = clip.end - _document.transitionAt(_selected) * clip.speed;
    if (_wantsPlayback && seconds >= playEnd - .025 && !_advancing) {
      _advancing = true;
      unawaited(_advanceClip());
    }
  }

  Future<void> _advanceClip() async {
    try {
      if (_selected < _document.clips.length - 1) {
        await _player?.pause();
        if (!mounted) return;
        setState(() => _selected++);
        await _syncSource();
        final next = _clip;
        if (next != null && mounted) {
          await _player?.seekTo(
            Duration(milliseconds: (next.start * 1000).round()),
          );
          if (_wantsPlayback && !_scrubbing) await _player?.play();
        }
      } else {
        _wantsPlayback = false;
        await _player?.pause();
      }
    } finally {
      _advancing = false;
    }
  }

  void _selectClip(int index, {bool transition = false}) {
    setState(() {
      _selected = index;
      _splitFraction = .5;
      _composedPreview = false;
      if (transition) _tool = 'Transition';
    });
    _queueSeek(VideoPreviewPosition.startOf(_document, index));
  }

  void _queueSeek(double seconds, {bool immediate = false}) {
    _position.value = seconds.clamp(0, _document.duration);
    _pendingSeek = _position.value;
    if (immediate) {
      _seekTimer?.cancel();
      unawaited(_flushSeek());
    } else if (_seekTimer?.isActive != true) {
      _seekTimer = Timer(
        const Duration(milliseconds: 40),
        () => unawaited(_flushSeek()),
      );
    }
  }

  Future<void> _flushSeek() async {
    if (_seekBusy ||
        !mounted ||
        _document.clips.isEmpty ||
        _exporting ||
        _rendering) {
      return;
    }
    _seekBusy = true;
    try {
      // One native seek in flight; discard intermediate drag events and apply
      // the latest target. A slider never queues dozens of codec seeks.
      while (_pendingSeek != null && mounted && !_exporting && !_rendering) {
        final seconds = _pendingSeek!;
        _pendingSeek = null;
        if (_composedPreview) {
          await _player?.seekTo(
            Duration(milliseconds: (seconds * 1000).round()),
          );
        } else {
          final target = VideoPreviewPosition.at(_document, seconds);
          if (_selected != target.index) {
            setState(() => _selected = target.index);
          }
          await _syncSource();
          if (!mounted || _exporting || _rendering) return;
          _splitFraction = (target.clipSeconds / _clip!.duration).clamp(
            .02,
            .98,
          );
          await _player?.seekTo(
            Duration(milliseconds: (target.sourceSeconds * 1000).round()),
          );
        }
      }
      if (_wantsPlayback && !_scrubbing) await _player?.play();
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not seek this clip. $error');
    } finally {
      _seekBusy = false;
    }
  }

  Future<void> _renderPreview() async {
    if (_rendering || _exporting || !mounted || _suspended) return;
    _sourceGeneration++;
    _pendingSeek = null;
    _seekTimer?.cancel();
    _wantsPlayback = false;
    final revision = _revision;
    final document = _document;
    setState(() {
      _rendering = true;
      _progress = 0;
      _stage = 'Preparing preview';
    });
    try {
      await _player?.pause();
      final result = await _renderer.render(
        document,
        shortEdge: 480,
        onProgress: _renderProgress,
      );
      if (!mounted || revision != _revision || _exporting) {
        await _renderer.release(result.path);
        return;
      }
      final nextPlayer = _makePlayer(result.path);
      try {
        await nextPlayer.initialize();
        await nextPlayer.setLooping(true);
      } catch (_) {
        await nextPlayer.dispose();
        await _renderer.release(result.path);
        rethrow;
      }
      if (!mounted || revision != _revision || _exporting) {
        await nextPlayer.dispose();
        await _renderer.release(result.path);
        return;
      }
      _sourceGeneration++;
      final previous = _player;
      previous?.removeListener(_playerChanged);
      final previousPath = _previewPath;
      final seek = Duration(milliseconds: (_position.value * 1000).round());
      setState(() {
        _player = nextPlayer;
        _previewPath = result.path;
        _previewRevision = revision;
        _composedPreview = true;
        _sourcePath = null;
        _loadingSource = false;
        _error = null;
      });
      nextPlayer.addListener(_playerChanged);
      await previous?.dispose();
      if (previousPath != null) await _renderer.release(previousPath);
      await nextPlayer.seekTo(
        seek < nextPlayer.value.duration ? seek : Duration.zero,
      );
    } on VideoRenderCancelled {
      // Superseded previews are expected while the user changes a recipe.
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = 'Composition preview could not be created. $error',
        );
      }
    } finally {
      _rendering = false;
      if (mounted) {
        setState(() {});
        if (revision != _revision && !_exporting) _schedulePreview();
      }
    }
  }

  void _renderProgress(double progress, String stage) {
    if (mounted) {
      setState(() {
        _progress = progress;
        _stage = stage;
      });
    }
  }

  Future<void> _addClips() async {
    if (_importing || _exporting) return;
    if (_document.clips.length >= VideoEditingLimits.clips) {
      _message(
        'This project supports ${VideoEditingLimits.clips} clips. Remove a clip or start another project to add more.',
      );
      return;
    }
    setState(() => _importing = true);
    try {
      final paths = await widget.pickVideos();
      if (_document.clips.length + paths.length > VideoEditingLimits.clips) {
        _message(
          'Choose up to ${VideoEditingLimits.clips - _document.clips.length} videos for this project. No timeline clips were changed.',
        );
        return;
      }
      final clips = <VideoClip>[];
      final failed = <String>[];
      for (final path in paths) {
        try {
          clips.add(await _renderer.probe(path));
        } catch (_) {
          failed.add(path.replaceAll('\\', '/').split('/').last);
        }
      }
      if (!mounted) return;
      if (clips.isNotEmpty) {
        final selected = _document.clips.length;
        _selected = selected;
        _change(_document.copyWith(clips: [..._document.clips, ...clips]));
        setState(() {
          _splitFraction = .5;
        });
      }
      if (failed.isNotEmpty) {
        _message(
          'Could not read: ${failed.join(', ')}. Try a supported MP4 or MOV video.',
        );
      }
    } catch (error) {
      _message('Video import failed. $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _pickMusic() async {
    try {
      final path = await widget.pickAudio();
      if (path != null && mounted) {
        _change(_document.copyWith(musicPath: path, musicStart: 0));
      }
    } catch (error) {
      _message('Audio could not be opened. $error');
    }
  }

  Future<void> _pickOverlay() async {
    if (_document.overlays.length >= VideoEditingLimits.overlays) {
      _message(
        'This project supports ${VideoEditingLimits.overlays} image overlays. Remove a layer before adding another.',
      );
      return;
    }
    try {
      final path = await widget.pickImage();
      if (path != null && mounted) {
        _change(
          _document.copyWith(
            overlays: [
              ..._document.overlays,
              VideoOverlay(
                id: _id(),
                path: path,
                end: _document.duration,
                x: .5,
                y: .5,
                width: .35,
                centered: true,
              ),
            ],
          ),
        );
        setState(() {
          _canvasTarget = 'overlay:${_document.overlays.last.id}';
          _tool = 'Overlay';
          _panelOpen = true;
        });
      }
    } catch (error) {
      _message('Image could not be opened. $error');
    }
  }

  Future<void> _rename() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _VideoNameDialog(title: _document.title),
    );
    if (title != null && title.isNotEmpty && mounted) {
      _change(_document.copyWith(title: title), render: false);
    }
  }

  Future<void> _exportOptions() async {
    final edge = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Make it yours',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Export to your device. Your media stays private.'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.hd_outlined),
                title: const Text('720p • Standard'),
                subtitle: const Text('Smaller file, ready to share'),
                onTap: () => Navigator.pop(context, 720),
              ),
              ListTile(
                leading: const Icon(Icons.high_quality_outlined),
                title: const Text('1080p • Full HD'),
                subtitle: const Text('More detail for your best work'),
                onTap: () => Navigator.pop(context, 1080),
              ),
              const ListTile(
                enabled: false,
                leading: Icon(Icons.four_k_outlined),
                title: Text('4K • Coming later'),
                subtitle: Text('Planned for a future update'),
              ),
            ],
          ),
        ),
      ),
    );
    if (edge == null || !mounted) return;
    if (!mounted) return;
    await _export(edge);
  }

  Future<void> _export(int edge) async {
    if (_exporting) return;
    _exportCancelled = false;
    _sourceGeneration++;
    _pendingSeek = null;
    _wantsPlayback = false;
    _seekTimer?.cancel();
    setState(() {
      _exporting = true;
      _progress = 0;
      _stage = 'Preparing export';
      _error = null;
    });
    String? rendered;
    try {
      await _renderer.cancel();
      await _job;
      await _player?.pause();
      await _save();
      if (!mounted) return;
      if (_exportCancelled) throw const VideoRenderCancelled();
      final result = await _renderer.render(
        _document,
        shortEdge: edge,
        onProgress: _renderProgress,
      );
      rendered = result.path;
      if (!mounted) return;
      final path = await widget.publishVideo(
        result.path,
        'FrameLab_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.accent,
              size: 42,
            ),
            title: const Text('Your video is ready'),
            content: SingleChildScrollView(
              child: SelectableText(
                '${result.width} × ${result.height} • ${result.codec}\n\nSaved to:\n$path',
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } on VideoRenderCancelled {
      _message('Export cancelled. Your project is safe.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Export failed. $error');
    } finally {
      if (rendered != null) await _renderer.release(rendered);
      if (mounted) {
        setState(() => _exporting = false);
        if (_previewRevision != _revision) _schedulePreview();
      }
    }
  }

  Future<void> _leave() async {
    if (_exporting) {
      _message('Cancel the export before leaving the editor.');
      return;
    }
    await _save();
    if (!mounted) return;
    if (_savedRevision != _revision) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Changes are not saved'),
          content: const Text(
            'Saving failed. Stay to retry, or leave without saving your latest changes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Save and close',
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: InkWell(
            onTap: _exporting ? null : _rename,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _document.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _saving
                      ? 'Saving…'
                      : _revision == 0 && _document.clips.isEmpty
                      ? 'Ready to edit'
                      : _savedRevision == _revision
                      ? 'Saved on device'
                      : 'Unsaved changes',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: !_exporting && _history.canUndo
                  ? () => _undo(false)
                  : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: !_exporting && _history.canRedo
                  ? () => _undo(true)
                  : null,
              icon: const Icon(Icons.redo_rounded),
            ),
            IconButton(
              tooltip: 'Export video',
              onPressed: _clip != null && !_exporting && !_importing
                  ? _exportOptions
                  : null,
              icon: const Icon(
                Icons.ios_share_rounded,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              if (_document.clips.isEmpty)
                _empty()
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxHeight < 390 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20;
                    final contents = <Widget>[
                      if (compact)
                        SizedBox(height: 210, child: _preview())
                      else
                        Expanded(child: _preview()),
                      _playback(),
                      _timeline(),
                      if (_panelOpen)
                        SizedBox(
                          height: compact
                              ? 210
                              : math.min(190, constraints.maxHeight * .28),
                          child: _toolPanel(),
                        ),
                      _toolbar(),
                    ];
                    return compact
                        ? SingleChildScrollView(
                            child: Column(children: contents),
                          )
                        : Column(children: contents);
                  },
                ),
              if (_exporting)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.background.withValues(alpha: .95),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.movie_creation_outlined,
                                size: 48,
                                color: AppColors.accent,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Creating your video',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              Text(_stage, textAlign: TextAlign.center),
                              const SizedBox(height: 20),
                              LinearProgressIndicator(value: _progress),
                              const SizedBox(height: 12),
                              Text('${(_progress * 100).round()}%'),
                              const SizedBox(height: 12),
                              const Text(
                                'Keep FrameLab open while exporting.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: () {
                                  _exportCancelled = true;
                                  unawaited(_renderer.cancel());
                                },
                                child: const Text('Cancel export'),
                              ),
                            ],
                          ),
                        ),
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

  Widget _empty() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.movie_creation_outlined,
                size: 66,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'A story starts here',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose a clip or a few. Trim, mix, add your own touch, and make something worth sharing.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _importing ? null : _addClips,
              icon: const Icon(Icons.add_rounded),
              label: Text(_importing ? 'Reading videos…' : 'Choose videos'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Offline editing • No account needed',
              style: TextStyle(fontSize: 12),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _preview() {
    final player = _player;
    final clip = _clip;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (player != null && player.value.isInitialized && clip != null)
            Center(
              child: AspectRatio(
                key: const ValueKey('video-preview-canvas'),
                aspectRatio: _composedPreview
                    ? player.value.aspectRatio
                    : _document.aspectRatio,
                child: _composedPreview
                    ? VideoPlayer(player)
                    : RepaintBoundary(child: _liveCanvas(player, clip)),
              ),
            )
          else if (_loadingSource)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            const Center(
              child: Icon(
                Icons.movie_outlined,
                size: 64,
                color: AppColors.border,
              ),
            ),
          if (_rendering)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_stage, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: _progress),
                      TextButton(
                        onPressed: () => unawaited(_renderer.cancel()),
                        child: const Text('Cancel preview'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _error = null);
                            _schedulePreview();
                            unawaited(_save());
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 10,
            left: 10,
            child: _badge(
              _composedPreview ? 'COMPOSITION PREVIEW' : 'LIVE PREVIEW',
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveCanvas(
    VideoPlayerController player,
    VideoClip clip,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final frame = Size(constraints.maxWidth, constraints.maxHeight);
      final placement = VideoCanvasPlacement.forClip(
        clip,
        canvasWidth: frame.width,
        canvasHeight: frame.height,
        sourceWidth: player.value.size.width,
        sourceHeight: player.value.size.height,
      );
      Widget video = ColorFiltered(
        key: const ValueKey('video-live-color'),
        colorFilter: ColorFilter.matrix(VideoPreviewColor.matrix(clip)),
        child: VideoPlayer(player),
      );
      if (clip.effect == VideoEffect.mirror) {
        video = Transform.flip(flipX: true, child: video);
      }
      if (clip.effect == VideoEffect.soft) {
        video = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
          child: video,
        );
      }
      final texture = Positioned(
        key: const ValueKey('video-live-crop'),
        left: placement.left,
        top: placement.top,
        width: placement.width,
        height: placement.height,
        child: video,
      );
      return ClipRect(
        key: _canvasKey,
        child: Listener(
          onPointerDown: (event) {
            if (_gestureSessionActive) {
              _canvasPointerOrigins.addAll(_canvasPointerPositions);
            }
            _canvasPointerOrigins[event.pointer] = event.position;
            _canvasPointerPositions[event.pointer] = event.position;
          },
          onPointerMove: (event) =>
              _canvasPointerPositions[event.pointer] = event.position,
          onPointerUp: (event) => _releaseCanvasPointer(event.pointer),
          onPointerCancel: (event) => _releaseCanvasPointer(event.pointer),
          child: ValueListenableBuilder<double>(
            valueListenable: _position,
            child: texture,
            builder: (context, position, videoTexture) {
              final local =
                  (position -
                          VideoPreviewPosition.startOf(_document, _selected))
                      .clamp(0, clip.duration);
              final fadeTime = math.min(.4, clip.duration / 3);
              final opacity = clip.effect == VideoEffect.fade
                  ? math
                        .min(
                          local / fadeTime,
                          (clip.duration - local) / fadeTime,
                        )
                        .clamp(0, 1)
                        .toDouble()
                  : 1.0;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('video-drag-clip'),
                      dragStartBehavior: DragStartBehavior.down,
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _selectCanvasTarget('clip'),
                      onScaleStart: (details) =>
                          _startCanvasGesture('clip', details, frame),
                      onScaleUpdate: _updateCanvasGesture,
                      onScaleEnd: (_) => _endCanvasGesture(),
                      child: Opacity(
                        opacity: opacity,
                        child: Stack(children: [videoTexture!]),
                      ),
                    ),
                  ),
                  if (clip.effect == VideoEffect.vignette ||
                      clip.filter == VideoFilter.cinema &&
                          clip.filterIntensity > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(
                                  alpha:
                                      .5 *
                                      (clip.effect == VideoEffect.vignette
                                          ? 1
                                          : clip.filterIntensity),
                                ),
                              ],
                              stops: const [.35, 1],
                              radius: .8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_canvasTarget == 'clip')
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: .65),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (final overlay in _document.overlays)
                    if (position >= overlay.start && position <= overlay.end)
                      _overlayOnCanvas(overlay, frame),
                  for (final text in _document.texts)
                    if (position >= text.start && position <= text.end)
                      _textOnCanvas(text, frame),
                  if (_gestureTarget != null && _snapX)
                    Positioned(
                      left: frame.width / 2,
                      top: 0,
                      bottom: 0,
                      child: const IgnorePointer(
                        child: SizedBox(
                          width: 1,
                          child: ColoredBox(color: AppColors.accent),
                        ),
                      ),
                    ),
                  if (_gestureTarget != null && _snapY)
                    Positioned(
                      top: frame.height / 2,
                      left: 0,
                      right: 0,
                      child: const IgnorePointer(
                        child: SizedBox(
                          height: 1,
                          child: ColoredBox(color: AppColors.accent),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  GlobalKey _layerKey(String target) =>
      _layerKeys.putIfAbsent(target, () => GlobalKey());

  Future<double> _overlayRatio(String path) =>
      _overlayRatios.putIfAbsent(path, () async {
        ui.ImmutableBuffer? buffer;
        ui.ImageDescriptor? descriptor;
        try {
          buffer = await ui.ImmutableBuffer.fromFilePath(path);
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          return descriptor.width / descriptor.height;
        } catch (_) {
          return 1;
        } finally {
          descriptor?.dispose();
          buffer?.dispose();
        }
      });

  Widget _overlayOnCanvas(VideoOverlay overlay, Size frame) =>
      FutureBuilder<double>(
        future: _overlayRatio(overlay.path),
        builder: (context, snapshot) {
          final ratio = snapshot.data ?? 1;
          final cacheWidth = math.max(
            1,
            (ratio >= 1 ? 1024.0 : 1024 * ratio).round(),
          );
          final cacheHeight = math.max(
            1,
            (ratio >= 1 ? 1024 / ratio : 1024.0).round(),
          );
          final size = Size(
            frame.width * overlay.width,
            frame.width * overlay.width / (snapshot.data ?? 1),
          );
          return _placedLayer(
            target: 'overlay:${overlay.id}',
            frame: frame,
            x: overlay.x,
            y: overlay.y,
            centered: overlay.centered,
            size: size,
            child: Opacity(
              opacity: overlay.opacity,
              child: Image.file(
                File(overlay.path),
                gaplessPlayback: true,
                fit: BoxFit.fill,
                // This provider key stays unchanged while dragging/pinching.
                // Both dimensions are bounded, including very tall images.
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
          );
        },
      );

  Widget _textOnCanvas(VideoText text, Size frame) {
    final style = TextStyle(
      fontFamily: text.font,
      fontSize: frame.height * text.size,
      color: Color(text.color),
      height: 1,
    );
    final painter = TextPainter(
      text: TextSpan(text: text.text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final padding = text.background ? frame.height * .0052 : 0.0;
    final size = Size(
      painter.width + padding * 2,
      painter.height + padding * 2,
    );
    painter.dispose();
    return _placedLayer(
      target: 'text:${text.id}',
      frame: frame,
      x: text.x,
      y: text.y,
      centered: text.centered,
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: text.background
              ? Colors.black.withValues(alpha: .55)
              : Colors.transparent,
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Text(
            text.text,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: style,
          ),
        ),
      ),
    );
  }

  Widget _placedLayer({
    required String target,
    required Size frame,
    required double x,
    required double y,
    required bool centered,
    required Size size,
    required Widget child,
  }) {
    final selected = target == _canvasTarget;
    return Positioned(
      left: centered
          ? frame.width * x - size.width / 2
          : (frame.width - size.width) * x,
      top: centered
          ? frame.height * y - size.height / 2
          : (frame.height - size.height) * y,
      width: size.width,
      height: size.height,
      child: Semantics(
        key: ValueKey('video-layer-$target'),
        label: target.startsWith('text:')
            ? 'Drag text; pinch to resize'
            : 'Drag image; pinch to resize',
        selected: selected,
        child: GestureDetector(
          key: _layerKey(target),
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectCanvasTarget(target),
          onDoubleTap: target.startsWith('text:')
              ? () => _editText(
                  _document.texts.firstWhere(
                    (text) => 'text:${text.id}' == target,
                  ),
                )
              : null,
          onScaleStart: (details) =>
              _startCanvasGesture(target, details, frame),
          onScaleUpdate: _updateCanvasGesture,
          onScaleEnd: (_) => _endCanvasGesture(),
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              child,
              if (selected)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  right: -7,
                  bottom: -7,
                  child: IgnorePointer(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.open_in_full_rounded,
                        color: Colors.black,
                        size: 12,
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

  void _selectCanvasTarget(String target, {bool openPanel = true}) {
    setState(() {
      _canvasTarget = target;
      _tool = target == 'clip'
          ? 'Canvas'
          : target.startsWith('text:')
          ? 'Text'
          : 'Overlay';
      if (openPanel) _panelOpen = true;
    });
  }

  void _startCanvasGesture(
    String target,
    ScaleStartDetails details,
    Size frame,
  ) {
    if (_exporting || _processingCutout || _composedPreview) return;
    _selectCanvasTarget(target, openPanel: false);
    _gestureTarget = target;
    final origins = _canvasPointerOrigins.values.toList();
    _gestureFocal = origins.isEmpty
        ? details.focalPoint
        : origins.reduce((a, b) => a + b) / origins.length.toDouble();
    final canvasBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    _gestureCanvasFocal =
        canvasBox?.globalToLocal(_gestureFocal) ??
        Offset(frame.width / 2, frame.height / 2);
    _gestureFrame = frame;
    _gestureClip = target == 'clip' ? _clip : null;
    _gestureOverlay = _document.overlays
        .where((layer) => 'overlay:${layer.id}' == target)
        .firstOrNull;
    _gestureText = _document.texts
        .where((text) => 'text:${text.id}' == target)
        .firstOrNull;
    if (_gestureClip case final clip?) {
      final placement = VideoCanvasPlacement.forClip(
        clip,
        canvasWidth: frame.width,
        canvasHeight: frame.height,
        sourceWidth: _player?.value.size.width,
        sourceHeight: _player?.value.size.height,
      );
      _gestureCenter = Offset(
        placement.left + placement.width / 2,
        placement.top + placement.height / 2,
      );
    } else {
      final layerSize =
          _layerKeys[target]?.currentContext?.size ?? const Size(40, 40);
      final x = _gestureOverlay?.x ?? _gestureText?.x ?? .5;
      final y = _gestureOverlay?.y ?? _gestureText?.y ?? .5;
      final centered =
          _gestureOverlay?.centered ?? _gestureText?.centered ?? true;
      _gestureCenter = centered
          ? Offset(frame.width * x, frame.height * y)
          : Offset(
              (frame.width - layerSize.width) * x + layerSize.width / 2,
              (frame.height - layerSize.height) * y + layerSize.height / 2,
            );
    }
    if (!_gestureSessionActive) _gestureChanged = false;
    _gestureSessionActive = true;
    _snapX = false;
    _snapY = false;
    _wantsPlayback = false;
    unawaited(_player?.pause());
    // Flutter accepts a scale after touch slop. Apply the full movement from
    // pointer down in that first frame, rather than dropping those pixels.
    _updateCanvasGesture(ScaleUpdateDetails(focalPoint: details.focalPoint));
  }

  void _updateCanvasGesture(ScaleUpdateDetails details) {
    if (_gestureTarget == null) return;
    final frame = _gestureFrame;
    final scale = details.scale;
    var center =
        _gestureCenter +
        (details.focalPoint - _gestureFocal) +
        (_gestureCenter - _gestureCanvasFocal) * (scale - 1);
    _snapX = (center.dx - frame.width / 2).abs() <= 5;
    _snapY = (center.dy - frame.height / 2).abs() <= 5;
    center = Offset(
      _snapX ? frame.width / 2 : center.dx,
      _snapY ? frame.height / 2 : center.dy,
    );
    if (_gestureClip case final initial?) {
      final zoom = (initial.zoom * scale).clamp(.1, 4).toDouble();
      final base = VideoCanvasPlacement.forClip(
        initial.copyWith(zoom: zoom, positionX: 0, positionY: 0),
        canvasWidth: frame.width,
        canvasHeight: frame.height,
        sourceWidth: _player?.value.size.width,
        sourceHeight: _player?.value.size.height,
      );
      _editClip(
        initial.copyWith(
          zoom: zoom,
          positionX: ((center.dx - base.left - base.width / 2) / frame.width)
              .clamp(-2, 2),
          positionY: ((center.dy - base.top - base.height / 2) / frame.height)
              .clamp(-2, 2),
        ),
        commit: false,
      );
    } else if (_gestureOverlay case final initial?) {
      _replaceOverlay(
        initial.copyWith(
          centered: true,
          x: (center.dx / frame.width).clamp(-.5, 1.5),
          y: (center.dy / frame.height).clamp(-.5, 1.5),
          width: (initial.width * scale).clamp(.03, 2),
        ),
        commit: false,
      );
    } else if (_gestureText case final initial?) {
      _replaceText(
        initial.copyWith(
          centered: true,
          x: (center.dx / frame.width).clamp(-.5, 1.5),
          y: (center.dy / frame.height).clamp(-.5, 1.5),
          size: (initial.size * scale).clamp(.02, .5),
        ),
        commit: false,
      );
    }
    _gestureChanged = true;
  }

  void _releaseCanvasPointer(int pointer) {
    _canvasPointerOrigins.remove(pointer);
    _canvasPointerPositions.remove(pointer);
    if (_gestureSessionActive && _canvasPointerPositions.isNotEmpty) {
      // The next scale segment begins from the current recipe and fingers.
      _canvasPointerOrigins.addAll(_canvasPointerPositions);
    }
    if (_canvasPointerPositions.isEmpty) {
      scheduleMicrotask(() {
        if (mounted && _gestureSessionActive) _finishCanvasSession();
      });
    }
  }

  void _endCanvasGesture() {
    if (_gestureTarget == null) return;
    if (_canvasPointerPositions.isEmpty) {
      _finishCanvasSession();
    } else {
      // Continue the same history gesture if a pinch becomes a one-finger drag.
      _canvasPointerOrigins.addAll(_canvasPointerPositions);
      setState(() {
        _gestureTarget = null;
        _snapX = false;
        _snapY = false;
      });
    }
  }

  void _finishCanvasSession() {
    if (!_gestureSessionActive) return;
    _gestureSessionActive = false;
    if (_gestureChanged) _commitGesture();
    setState(() {
      _gestureTarget = null;
      _snapX = false;
      _snapY = false;
    });
  }

  void _replaceOverlay(VideoOverlay overlay, {bool commit = true}) => _change(
    _document.copyWith(
      overlays: _document.overlays
          .map((layer) => layer.id == overlay.id ? overlay : layer)
          .toList(),
    ),
    commit: commit,
  );

  void _replaceText(VideoText text, {bool commit = true}) => _change(
    _document.copyWith(
      texts: _document.texts
          .map((layer) => layer.id == text.id ? text : layer)
          .toList(),
    ),
    commit: commit,
  );

  Widget _placementControls(String target) => Wrap(
    spacing: 2,
    children: [
      IconButton(
        tooltip: 'Move selected layer left',
        onPressed: () => _nudgeTarget(target, const Offset(-.01, 0)),
        icon: const Icon(Icons.arrow_left_rounded),
      ),
      IconButton(
        tooltip: 'Move selected layer up',
        onPressed: () => _nudgeTarget(target, const Offset(0, -.01)),
        icon: const Icon(Icons.arrow_drop_up_rounded),
      ),
      IconButton(
        tooltip: 'Center selected layer',
        onPressed: () => _nudgeTarget(target, Offset.zero, center: true),
        icon: const Icon(Icons.center_focus_strong_rounded),
      ),
      IconButton(
        tooltip: 'Move selected layer down',
        onPressed: () => _nudgeTarget(target, const Offset(0, .01)),
        icon: const Icon(Icons.arrow_drop_down_rounded),
      ),
      IconButton(
        tooltip: 'Move selected layer right',
        onPressed: () => _nudgeTarget(target, const Offset(.01, 0)),
        icon: const Icon(Icons.arrow_right_rounded),
      ),
    ],
  );

  void _nudgeTarget(String target, Offset delta, {bool center = false}) {
    if (target == 'clip') {
      final clip = _clip!;
      _editClip(
        clip.copyWith(
          positionX: center ? 0 : (clip.positionX + delta.dx).clamp(-2, 2),
          positionY: center ? 0 : (clip.positionY + delta.dy).clamp(-2, 2),
          cropX: center ? .5 : clip.cropX,
          cropY: center ? .5 : clip.cropY,
        ),
      );
      return;
    }
    final overlay = _document.overlays
        .where((layer) => 'overlay:${layer.id}' == target)
        .firstOrNull;
    final text = _document.texts
        .where((layer) => 'text:${layer.id}' == target)
        .firstOrNull;
    if (overlay == null && text == null) return;
    final frame = _canvasKey.currentContext?.size ?? const Size(320, 180);
    final size = _layerKeys[target]?.currentContext?.size ?? const Size(40, 40);
    final centered = overlay?.centered ?? text!.centered;
    var x = overlay?.x ?? text!.x;
    var y = overlay?.y ?? text!.y;
    if (!centered) {
      x = ((frame.width - size.width) * x + size.width / 2) / frame.width;
      y = ((frame.height - size.height) * y + size.height / 2) / frame.height;
    }
    x = center ? .5 : (x + delta.dx).clamp(-.5, 1.5);
    y = center ? .5 : (y + delta.dy).clamp(-.5, 1.5);
    if (overlay != null) {
      _replaceOverlay(overlay.copyWith(x: x, y: y, centered: true));
    }
    if (text != null) _replaceText(text.copyWith(x: x, y: y, centered: true));
  }

  Widget _badge(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    ),
  );

  Widget _playback() => ValueListenableBuilder<double>(
    valueListenable: _position,
    builder: (context, position, _) {
      final player = _player;
      final available = player != null && player.value.isInitialized;
      return Row(
        children: [
          IconButton(
            tooltip: available && player.value.isPlaying
                ? 'Pause preview'
                : 'Play preview',
            onPressed: !available || _rendering
                ? null
                : () async {
                    _wantsPlayback = !player.value.isPlaying;
                    if (_wantsPlayback) {
                      if (position >= _document.duration - .04) {
                        _queueSeek(0, immediate: true);
                      } else {
                        await player.play();
                      }
                    } else {
                      await player.pause();
                    }
                    if (mounted) setState(() {});
                  },
            icon: Icon(
              available && player.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
          SizedBox(
            width: 52,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _time(position),
                style: const TextStyle(fontSize: 11, fontFamily: 'StudioMono'),
              ),
            ),
          ),
          Expanded(
            child: Slider(
              key: const ValueKey('video-timeline-scrubber'),
              value: position.clamp(0, math.max(.01, _document.duration)),
              max: math.max(.01, _document.duration),
              onChangeStart: (_) {
                _scrubbing = true;
                unawaited(_player?.pause());
              },
              onChanged: _rendering ? null : _queueSeek,
              onChangeEnd: (value) {
                _scrubbing = false;
                _queueSeek(value, immediate: true);
              },
            ),
          ),
          SizedBox(
            width: 52,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _time(_document.duration),
                style: const TextStyle(fontSize: 11, fontFamily: 'StudioMono'),
              ),
            ),
          ),
          IconButton(
            tooltip: _composedPreview
                ? 'Back to live editing'
                : 'Preview composition with music and transitions',
            onPressed: _rendering || _loadingSource
                ? null
                : () {
                    if (_composedPreview) {
                      setState(() => _composedPreview = false);
                      _schedulePreview();
                    } else {
                      _job = _renderPreview();
                    }
                  },
            icon: Icon(
              _composedPreview
                  ? Icons.edit_rounded
                  : Icons.movie_filter_outlined,
              size: 22,
            ),
          ),
        ],
      );
    },
  );

  Future<String?> _thumbnail(VideoClip clip, int sample) {
    final loader = widget.thumbnailLoader;
    if (loader == null) return Future.value(null);
    final anchor = _thumbnailAnchors.putIfAbsent(
      clip.id,
      () => (clip.start, clip.end),
    );
    final seconds =
        anchor.$1 + math.max(0, anchor.$2 - anchor.$1 - .04) * sample / 2;
    final key = '${clip.path}:$seconds';
    return _thumbnails.putIfAbsent(key, () {
      if (_thumbnails.length >= 48) _thumbnails.remove(_thumbnails.keys.first);
      return Future<String?>.sync(
        () => loader(clip.path, seconds),
      ).catchError((_) => null);
    });
  }

  Widget _filmstrip(VideoClip clip, bool active) => Stack(
    fit: StackFit.expand,
    children: [
      if (widget.thumbnailLoader != null)
        Row(
          children: [
            for (var sample = 0; sample < 3; sample++)
              Expanded(
                child: FutureBuilder<String?>(
                  future: _thumbnail(clip, sample),
                  builder: (context, snapshot) => snapshot.data == null
                      ? ColoredBox(
                          color: AppColors.surfaceRaised,
                          child: const Center(
                            child: Icon(
                              Icons.videocam_outlined,
                              size: 18,
                              color: AppColors.muted,
                            ),
                          ),
                        )
                      : Image.file(
                          File(snapshot.data!),
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: AppColors.surfaceRaised),
                        ),
                ),
              ),
          ],
        ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: .25),
              Colors.black.withValues(alpha: .8),
            ],
          ),
        ),
      ),
      if (active) ColoredBox(color: AppColors.primary.withValues(alpha: .06)),
    ],
  );

  Widget _timeline() => Container(
    height: math.max(100, 58 + MediaQuery.textScalerOf(context).scale(42)),
    color: AppColors.surface,
    child: Row(
      children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 9, 0, 9),
            itemCount: _document.clips.length,
            itemBuilder: (context, index) {
              final clip = _document.clips[index];
              final active = index == _selected;
              return Row(
                children: [
                  Semantics(
                    label:
                        'Clip ${index + 1}, ${clip.name}, ${clip.duration.toStringAsFixed(1)} seconds',
                    selected: active,
                    button: true,
                    child: InkWell(
                      onTap: () => _selectClip(index),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: (clip.duration * 16).clamp(100, 320),
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: active
                                ? [
                                    AppColors.primary.withValues(alpha: .22),
                                    AppColors.primary.withValues(alpha: .08),
                                  ]
                                : [AppColors.surfaceRaised, AppColors.surface],
                          ),
                          border: Border.all(
                            color: active
                                ? AppColors.primary
                                : AppColors.border,
                            width: active ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _filmstrip(clip, active),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.videocam_outlined,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${index + 1}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    const Spacer(),
                                    if (clip.volume == 0)
                                      const Icon(
                                        Icons.volume_off_outlined,
                                        size: 13,
                                      ),
                                  ],
                                ),
                                Text(
                                  clip.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${clip.duration.toStringAsFixed(1)}s  •  ${clip.speed.toStringAsFixed(2)}×',
                                  style: const TextStyle(fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (index < _document.clips.length - 1)
                    IconButton(
                      tooltip:
                          'Transition after clip ${index + 1}: ${clip.transition.name}',
                      onPressed: () => _selectClip(index, transition: true),
                      icon: Icon(
                        clip.transition == VideoTransition.cut
                            ? Icons.add_rounded
                            : Icons.compare_arrows_rounded,
                        color: clip.transition == VideoTransition.cut
                            ? AppColors.muted
                            : AppColors.accent,
                        size: 18,
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                ],
              );
            },
          ),
        ),
        IconButton(
          tooltip: 'Add videos to timeline',
          onPressed: _importing ? null : _addClips,
          icon: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.accent,
                ),
        ),
      ],
    ),
  );

  Widget _toolbar() => Container(
    height: math.max(76, 48 + MediaQuery.textScalerOf(context).scale(28)),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: ListView.separated(
      key: const ValueKey('video-editor-toolbar'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _tools.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, i) {
        final tool = _tools[i];
        return Semantics(
          selected: _tool == tool.$1,
          button: true,
          label: tool.$1,
          child: InkWell(
            onTap: () => setState(() {
              _panelOpen = true;
              _tool = tool.$1;
              if (_tool == 'Canvas' || _tool == 'Cutout') {
                _canvasTarget = 'clip';
              }
              if (_tool == 'Overlay' && _activeOverlay != null) {
                _canvasTarget = 'overlay:${_activeOverlay!.id}';
              }
            }),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 69,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    tool.$2,
                    color: _tool == tool.$1
                        ? AppColors.primary
                        : AppColors.muted,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tool.$1,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: _tool == tool.$1
                          ? AppColors.primary
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _toolPanel() {
    final clip = _clip!;
    return SingleChildScrollView(
      key: ValueKey(_tool),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _tool == 'Trim'
                      ? 'Clip ${_selected + 1} • Trim & arrange'
                      : _tool,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Done with tool',
                onPressed: () => setState(() => _panelOpen = false),
                icon: const Icon(
                  Icons.check_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...switch (_tool) {
            'Trim' => _trimTools(clip),
            'Canvas' => _canvasTools(clip),
            'Cutout' => _cutoutTools(clip),
            'Speed' => _speedTools(clip),
            'Audio' => _audioTools(clip),
            'Text' => _textTools(),
            'Adjust' => _adjustTools(clip),
            'Filters' => _filterTools(clip),
            'Effects' => _effectTools(clip),
            'Transition' => _transitionTools(clip),
            'Overlay' => _overlayTools(),
            _ => <Widget>[],
          },
        ],
      ),
    );
  }

  List<Widget> _trimTools(VideoClip clip) => [
    Wrap(
      spacing: 24,
      runSpacing: 4,
      children: [
        Text('In ${_time(clip.start)}', style: const TextStyle(fontSize: 12)),
        Text('Out ${_time(clip.end)}', style: const TextStyle(fontSize: 12)),
      ],
    ),
    RangeSlider(
      values: RangeValues(clip.start, clip.end),
      min: 0,
      max: clip.sourceDuration,
      labels: RangeLabels(_time(clip.start), _time(clip.end)),
      onChanged: (value) {
        if (value.end - value.start >= .05) {
          _editClip(
            clip.copyWith(start: value.start, end: value.end),
            commit: false,
          );
        }
      },
      onChangeEnd: (_) => _commitGesture(),
    ),
    _slider(
      'Split at ${_time(clip.start + (clip.end - clip.start) * _splitFraction)}',
      _splitFraction,
      .02,
      .98,
      (v) {
        setState(() => _splitFraction = v);
        _queueSeek(
          VideoPreviewPosition.startOf(_document, _selected) +
              clip.duration * v,
        );
      },
      commit: false,
    ),
    Wrap(
      spacing: 6,
      children: [
        TextButton.icon(
          onPressed: clip.end - clip.start <= .1
              ? null
              : () {
                  if (_document.clips.length >= VideoEditingLimits.clips) {
                    _message(
                      'Remove a clip before splitting. A project supports ${VideoEditingLimits.clips} clips.',
                    );
                    return;
                  }
                  final source =
                      clip.start + (clip.end - clip.start) * _splitFraction;
                  try {
                    final clips = [..._document.clips];
                    clips.replaceRange(
                      _selected,
                      _selected + 1,
                      splitVideoClip(clip, source, _id()),
                    );
                    _change(_document.copyWith(clips: clips));
                  } catch (_) {
                    _message(
                      'Move the split point further from the clip edge.',
                    );
                  }
                },
          icon: const Icon(Icons.content_cut_rounded, size: 17),
          label: const Text('Split'),
        ),
        IconButton(
          tooltip: 'Move clip earlier',
          onPressed: _selected > 0 ? () => _moveClip(-1) : null,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        IconButton(
          tooltip: 'Move clip later',
          onPressed: _selected < _document.clips.length - 1
              ? () => _moveClip(1)
              : null,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
        IconButton(
          tooltip: 'Duplicate clip',
          onPressed: () {
            final clips = [..._document.clips]
              ..insert(_selected + 1, clip.copyWith(id: _id()));
            _change(_document.copyWith(clips: clips));
          },
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: 'Remove clip',
          onPressed: () {
            final clips = [..._document.clips]..removeAt(_selected);
            _change(_document.copyWith(clips: clips));
          },
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
    const Text(
      'Clips are merged in timeline order when you export.',
      style: TextStyle(fontSize: 11),
    ),
  ];

  void _moveClip(int direction) {
    final index = _selected;
    final clips = [..._document.clips];
    final clip = clips.removeAt(index);
    clips.insert(index + direction, clip);
    _selected = index + direction;
    _change(_document.copyWith(clips: clips));
  }

  List<Widget> _canvasTools(VideoClip clip) => [
    Wrap(
      spacing: 6,
      children: VideoCanvas.values
          .map(
            (value) => ChoiceChip(
              label: Text(switch (value) {
                VideoCanvas.original => 'Original',
                VideoCanvas.landscape => '16:9',
                VideoCanvas.portrait => '9:16',
                VideoCanvas.square => '1:1',
                VideoCanvas.social => '4:5',
              }),
              selected: _document.canvas == value,
              onSelected: (_) => _change(_document.copyWith(canvas: value)),
            ),
          )
          .toList(),
    ),
    Wrap(
      spacing: 8,
      children: [
        for (final fit in VideoFit.values)
          ChoiceChip(
            key: ValueKey('video-fit-${fit.name}'),
            label: Text(fit == VideoFit.fill ? 'Fill' : 'Fit'),
            selected: clip.fit == fit,
            onSelected: (_) => _editClip(
              clip.copyWith(
                fit: fit,
                zoom: 1,
                positionX: 0,
                positionY: 0,
                cropX: .5,
                cropY: .5,
              ),
            ),
          ),
        TextButton.icon(
          onPressed: () => _editClip(
            clip.copyWith(
              zoom: 1,
              positionX: 0,
              positionY: 0,
              cropX: .5,
              cropY: .5,
            ),
          ),
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Reset'),
        ),
      ],
    ),
    _placementControls('clip'),
    const Text(
      'Drag the video to position it. Pinch to resize. Cyan guides snap to the canvas center.',
      style: TextStyle(fontSize: 11, color: AppColors.muted),
    ),
  ];

  List<Widget> _cutoutTools(VideoClip clip) => [
    FilledButton.icon(
      onPressed: widget.removeVideoBackground == null || _processingCutout
          ? null
          : _cutoutVideo,
      icon: const Icon(Icons.person_outline_rounded),
      label: Text(
        _processingCutout ? 'Processing on device…' : 'Auto & manual cutout',
      ),
    ),
    const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(
        'Choose auto removal, brush cleanup and a replacement background. Applies to this trimmed clip offline; processing has progress and cancel.',
        style: TextStyle(fontSize: 11, color: AppColors.muted),
      ),
    ),
    if (clip.cutoutOriginal != null)
      TextButton.icon(
        onPressed: () {
          final original = clip.cutoutOriginal!;
          _editClip(
            clip.copyWith(
              path: original.path,
              start: original.start,
              end: original.end,
              sourceDuration: original.sourceDuration,
              width: original.width,
              height: original.height,
              hasAudio: original.hasAudio,
              clearCutoutOriginal: true,
            ),
          );
        },
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text('Restore original video'),
      ),
  ];

  Future<void> _cutoutVideo() async {
    final clip = _clip;
    if (clip == null ||
        widget.removeVideoBackground == null ||
        _processingCutout) {
      return;
    }
    setState(() => _processingCutout = true);
    _wantsPlayback = false;
    unawaited(_player?.pause());
    try {
      final result = await widget.removeVideoBackground!(clip);
      if (result != null && mounted) {
        final index = _document.clips.indexWhere((item) => item.id == clip.id);
        if (index >= 0) {
          final clips = [..._document.clips];
          clips[index] = result;
          _change(_document.copyWith(clips: clips));
        }
      }
    } catch (error) {
      _message('Video cutout could not be completed. $error');
    } finally {
      if (mounted) setState(() => _processingCutout = false);
    }
  }

  List<Widget> _speedTools(VideoClip clip) => [
    _slider(
      'Playback • ${clip.speed.toStringAsFixed(2)}×',
      clip.speed,
      .25,
      4,
      (v) => _editClip(clip.copyWith(speed: v), commit: false),
    ),
    Wrap(
      spacing: 6,
      children: [.25, .5, 1.0, 1.5, 2.0, 4.0]
          .map(
            (value) => ChoiceChip(
              label: Text('$value×'),
              selected: (clip.speed - value).abs() < .01,
              onSelected: (_) => _editClip(clip.copyWith(speed: value)),
            ),
          )
          .toList(),
    ),
    const SizedBox(height: 10),
    Text(
      'Edited clip: ${clip.duration.toStringAsFixed(1)} seconds. Audio follows speed with pitch preserved.',
      style: const TextStyle(fontSize: 12),
    ),
  ];

  List<Widget> _audioTools(VideoClip clip) => [
    Row(
      children: [
        Expanded(
          child: Text(
            clip.hasAudio ? 'Clip audio' : 'This clip has no audio',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton.icon(
          onPressed: clip.hasAudio
              ? () => _editClip(clip.copyWith(volume: clip.volume == 0 ? 1 : 0))
              : null,
          icon: Icon(
            clip.volume == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            size: 18,
          ),
          label: Text(clip.volume == 0 ? 'Unmute' : 'Mute'),
        ),
      ],
    ),
    _slider(
      'Volume • ${(clip.volume * 100).round()}%',
      clip.volume,
      0,
      2,
      (v) => _editClip(clip.copyWith(volume: v), commit: false),
    ),
    Row(
      children: [
        Expanded(
          child: Text(
            _document.musicPath == null
                ? 'Add your own soundtrack'
                : _document.musicPath!.replaceAll('\\', '/').split('/').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Choose music',
          onPressed: _pickMusic,
          icon: const Icon(Icons.library_music_outlined),
        ),
        if (_document.musicPath != null)
          IconButton(
            tooltip: 'Remove music',
            onPressed: () => _change(_document.copyWith(removeMusic: true)),
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    ),
    if (_document.musicPath != null) ...[
      _slider(
        'Music volume • ${(_document.musicVolume * 100).round()}%',
        _document.musicVolume,
        0,
        2,
        (v) => _change(_document.copyWith(musicVolume: v), commit: false),
      ),
      _slider(
        'Music starts at ${_time(_document.musicStart)}',
        _document.musicStart,
        0,
        math.max(300, _document.musicStart),
        (v) => _change(_document.copyWith(musicStart: v), commit: false),
      ),
      const Text(
        'Music loops in export. Use composition preview to hear the full mix.',
        style: TextStyle(fontSize: 11),
      ),
    ],
  ];

  List<Widget> _adjustTools(VideoClip clip) => [
    _slider(
      'Brightness',
      clip.brightness,
      -.5,
      .5,
      (v) => _editClip(clip.copyWith(brightness: v), commit: false),
    ),
    _slider(
      'Contrast',
      clip.contrast,
      0,
      2,
      (v) => _editClip(clip.copyWith(contrast: v), commit: false),
    ),
    _slider(
      'Saturation',
      clip.saturation,
      0,
      2,
      (v) => _editClip(clip.copyWith(saturation: v), commit: false),
    ),
    _slider(
      'Exposure',
      clip.exposure,
      -2,
      2,
      (v) => _editClip(clip.copyWith(exposure: v), commit: false),
    ),
    TextButton.icon(
      onPressed: () => _editClip(
        clip.copyWith(brightness: 0, contrast: 1, saturation: 1, exposure: 0),
      ),
      icon: const Icon(Icons.restart_alt_rounded, size: 18),
      label: const Text('Reset adjustments'),
    ),
  ];

  List<Widget> _filterTools(VideoClip clip) => [
    FilterStrip<VideoFilter>(
      options: VideoFilter.values
          .map(
            (filter) => FilterOption(
              value: filter,
              label: _label(filter.name),
              group: switch (filter) {
                VideoFilter.original => 'All',
                VideoFilter.mono => 'Classic',
                VideoFilter.cinema => 'Film',
                _ => 'Color',
              },
            ),
          )
          .toList(),
      selected: clip.filter,
      onSelected: (filter) => _editClip(_clip!.copyWith(filter: filter)),
      previewBuilder: (filter) => FutureBuilder<String?>(
        future: _thumbnail(clip, 1),
        builder: (context, snapshot) => ColorFiltered(
          colorFilter: ColorFilter.matrix(
            VideoPreviewColor.matrix(
              clip.copyWith(
                filter: filter,
                filterIntensity: 1,
                brightness: 0,
                contrast: 1,
                saturation: 1,
                exposure: 0,
              ),
            ),
          ),
          child: snapshot.data == null
              ? const ColoredBox(
                  color: AppColors.surfaceRaised,
                  child: Center(
                    child: Icon(Icons.movie_outlined, color: AppColors.muted),
                  ),
                )
              : Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
        ),
      ),
      enabled: !_exporting && !_processingCutout,
      strengthEnabled: clip.filter != VideoFilter.original,
      intensity: clip.filterIntensity,
      onIntensityChanged: (value) =>
          _editClip(_clip!.copyWith(filterIntensity: value), commit: false),
      onIntensityChangeEnd: _commitGesture,
    ),
    const Text(
      'Tap a look, then adjust strength. Filters work offline with no downloads or account.',
      style: TextStyle(fontSize: 11, color: AppColors.muted),
    ),
  ];

  List<Widget> _effectTools(VideoClip clip) => [
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: VideoEffect.values
          .map(
            (effect) => ChoiceChip(
              label: Text(_label(effect.name)),
              selected: clip.effect == effect,
              onSelected: (_) async {
                if (mounted) _editClip(_clip!.copyWith(effect: effect));
              },
            ),
          )
          .toList(),
    ),
    const SizedBox(height: 12),
    const Text(
      'Vignette frames the subject. Mirror flips the clip. Fade gently opens and closes the shot.',
      style: TextStyle(fontSize: 12),
    ),
  ];

  List<Widget> _transitionTools(VideoClip clip) =>
      _selected == _document.clips.length - 1
      ? [
          const Text(
            'Add another clip, then select a join between clips to create a transition.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addClips,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add next clip'),
          ),
        ]
      : [
          Text(
            'Between clips ${_selected + 1} and ${_selected + 2}',
            style: const TextStyle(fontSize: 12),
          ),
          Wrap(
            spacing: 6,
            children: VideoTransition.values
                .map(
                  (transition) => ChoiceChip(
                    label: Text(_label(transition.name)),
                    selected: clip.transition == transition,
                    onSelected: (_) async {
                      if (mounted) {
                        _editClip(_clip!.copyWith(transition: transition));
                      }
                    },
                  ),
                )
                .toList(),
          ),
          if (clip.transition != VideoTransition.cut)
            _slider(
              'Overlap • ${_document.transitionAt(_selected).toStringAsFixed(2)}s',
              clip.transitionDuration,
              .1,
              2,
              (v) => _editClip(
                clip.copyWith(transitionDuration: v),
                commit: false,
              ),
            ),
          const Text(
            'Transitions overlap adjacent clips. Audio fades across the same join.',
            style: TextStyle(fontSize: 11),
          ),
        ];

  List<Widget> _textTools() => [
    OutlinedButton.icon(
      onPressed: () => _editText(),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add text'),
    ),
    for (final text in _document.texts)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(text.text, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_time(text.start)} – ${_time(math.min(text.end, _document.duration))} • ${text.font.replaceFirst('Studio', '')}',
          style: const TextStyle(fontSize: 11),
        ),
        onTap: () => _editText(text),
        trailing: IconButton(
          tooltip: 'Delete text',
          onPressed: () => _change(
            _document.copyWith(
              texts: _document.texts.where((t) => t.id != text.id).toList(),
            ),
          ),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ),
    if (_document.texts.isEmpty)
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Titles, captions, a thought. Pick a font, position, color and when it appears.',
          style: TextStyle(fontSize: 12),
        ),
      ),
    const Text(
      'Tap text on the canvas to select it. Drag to move; pinch to resize; double-tap to edit.',
      style: TextStyle(fontSize: 11, color: AppColors.muted),
    ),
    if (_canvasTarget.startsWith('text:')) _placementControls(_canvasTarget),
  ];

  Future<void> _editText([VideoText? existing]) async {
    if (existing == null &&
        _document.texts.length >= VideoEditingLimits.textLayers) {
      _message(
        'This project supports ${VideoEditingLimits.textLayers} text layers. Edit or remove an existing layer to add another.',
      );
      return;
    }
    final result = await showModalBottomSheet<VideoText>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TextEditor(
        text:
            existing ??
            VideoText(
              id: _id(),
              text: 'Your story',
              end: _document.duration,
              x: .5,
              y: .5,
              centered: true,
            ),
        duration: _document.duration,
        colors: _colors,
      ),
    );
    if (result == null || !mounted) return;
    final texts = [..._document.texts];
    final index = texts.indexWhere((text) => text.id == result.id);
    if (index < 0) {
      texts.add(result);
    } else {
      texts[index] = result;
    }
    _change(_document.copyWith(texts: texts));
    setState(() => _canvasTarget = 'text:${result.id}');
  }

  List<Widget> _overlayTools() {
    final overlay = _activeOverlay;
    return [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickOverlay,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add image overlay'),
            ),
          ),
          if (overlay != null)
            IconButton(
              tooltip: 'Remove overlay',
              onPressed: () => _change(
                _document.copyWith(
                  overlays: _document.overlays
                      .where((layer) => layer.id != overlay.id)
                      .toList(),
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      if (_document.overlays.length > 1)
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < _document.overlays.length; i++)
              ChoiceChip(
                label: Text('Image ${i + 1}'),
                selected: _document.overlays[i].id == overlay?.id,
                onSelected: (_) =>
                    _selectCanvasTarget('overlay:${_document.overlays[i].id}'),
              ),
          ],
        ),
      if (overlay != null) ...[
        const Text(
          'Drag the selected image to move it. Pinch to resize.',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        _placementControls('overlay:${overlay.id}'),
        _slider(
          'Opacity',
          overlay.opacity,
          0,
          1,
          (v) => _updateOverlay(opacity: v),
        ),
        if (overlay.originalPath != null)
          TextButton.icon(
            onPressed: () => _replaceOverlay(
              VideoOverlay(
                id: overlay.id,
                path: overlay.originalPath!,
                x: overlay.x,
                y: overlay.y,
                width: overlay.width,
                opacity: overlay.opacity,
                start: overlay.start,
                end: overlay.end,
                centered: overlay.centered,
              ),
            ),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Restore original image'),
          ),
        if (widget.refineImageBackground != null)
          TextButton.icon(
            onPressed: _processingCutout ? null : () => _cutoutOverlay(overlay),
            icon: const Icon(Icons.person_outline_rounded),
            label: const Text('Auto & manual image cutout'),
          ),
        Text(
          'Visible ${_time(overlay.start)} – ${_time(math.min(overlay.end, _document.duration))}',
          style: const TextStyle(fontSize: 12),
        ),
        RangeSlider(
          values: RangeValues(
            overlay.start.clamp(0, _document.duration),
            overlay.end.clamp(0, _document.duration),
          ),
          min: 0,
          max: _document.duration,
          onChanged: (v) => _updateOverlay(start: v.start, end: v.end),
          onChangeEnd: (_) => _commitGesture(),
        ),
      ] else
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Layer logos, stickers and photos. Transparent PNG images keep their transparency.',
            style: TextStyle(fontSize: 12),
          ),
        ),
    ];
  }

  Future<void> _cutoutOverlay(VideoOverlay overlay) async {
    if (widget.refineImageBackground == null || _processingCutout) return;
    setState(() => _processingCutout = true);
    _wantsPlayback = false;
    unawaited(_player?.pause());
    try {
      final path = await widget.refineImageBackground!(
        overlay.originalPath ?? overlay.path,
        overlay.originalPath == null ? null : overlay.path,
      );
      if (path != null &&
          mounted &&
          _document.overlays.any((layer) => layer.id == overlay.id)) {
        final current = _document.overlays.firstWhere(
          (layer) => layer.id == overlay.id,
        );
        _replaceOverlay(
          VideoOverlay(
            id: current.id,
            originalPath: current.originalPath ?? current.path,
            path: path,
            x: current.x,
            y: current.y,
            width: current.width,
            opacity: current.opacity,
            start: current.start,
            end: current.end,
            centered: current.centered,
          ),
        );
      }
    } catch (error) {
      _message('Image cutout could not be completed. $error');
    } finally {
      if (mounted) setState(() => _processingCutout = false);
    }
  }

  void _updateOverlay({double? opacity, double? start, double? end}) {
    final overlay = _activeOverlay;
    if (overlay != null) {
      _replaceOverlay(
        overlay.copyWith(opacity: opacity, start: start, end: end),
        commit: false,
      );
    }
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    bool commit = true,
  }) => Row(
    children: [
      SizedBox(
        width: 120,
        child: Text(label, style: const TextStyle(fontSize: 11), maxLines: 2),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: commit ? (_) => _commitGesture() : null,
        ),
      ),
    ],
  );
  String _label(String text) => '${text[0].toUpperCase()}${text.substring(1)}';
}

class _VideoNameDialog extends StatefulWidget {
  const _VideoNameDialog({required this.title});
  final String title;

  @override
  State<_VideoNameDialog> createState() => _VideoNameDialogState();
}

class _VideoNameDialogState extends State<_VideoNameDialog> {
  late final _controller = TextEditingController(text: widget.title);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name your video'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Project name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

class _TextEditor extends StatefulWidget {
  const _TextEditor({
    required this.text,
    required this.duration,
    required this.colors,
  });
  final VideoText text;
  final double duration;
  final List<int> colors;
  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late TextEditingController _text;
  late double _x, _y, _size, _start, _end;
  late int _color;
  late String _font;
  late bool _background;
  @override
  void initState() {
    super.initState();
    final text = widget.text;
    _text = TextEditingController(text: text.text);
    _x = text.x;
    _y = text.y;
    _size = text.size;
    _color = text.color;
    _font = text.font;
    _background = text.background;
    _start = text.start.clamp(0, widget.duration);
    _end = text.end.clamp(_start, widget.duration);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Make a statement',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Save text',
                  onPressed: () {
                    if (_text.text.trim().isEmpty) return;
                    Navigator.pop(
                      context,
                      VideoText(
                        id: widget.text.id,
                        text: _text.text.trim(),
                        x: _x,
                        y: _y,
                        size: _size,
                        color: _color,
                        font: _font,
                        background: _background,
                        centered: widget.text.centered,
                        start: _start,
                        end: _end,
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.check_rounded,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    controller: _text,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 5,
                    style: TextStyle(fontFamily: _font, color: Color(_color)),
                    decoration: const InputDecoration(
                      labelText: 'Your text',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children:
                        const [
                              'StudioSans',
                              'StudioSerif',
                              'StudioMono',
                              'StudioScript',
                              'StudioDisplay',
                            ]
                            .map(
                              (font) => ChoiceChip(
                                label: Text(
                                  font.replaceFirst('Studio', ''),
                                  style: TextStyle(fontFamily: font),
                                ),
                                selected: _font == font,
                                onSelected: (_) async {
                                  if (mounted) setState(() => _font = font);
                                },
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: widget.colors
                        .map(
                          (color) => Semantics(
                            label: 'Text color ${color.toRadixString(16)}',
                            selected: _color == color,
                            child: InkWell(
                              onTap: () => setState(() => _color = color),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Color(color),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _color == color
                                        ? AppColors.primary
                                        : AppColors.border,
                                    width: _color == color ? 4 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  _slider('Font size', _size, .02, .5, (v) => _size = v),
                  const Text(
                    'Place text by dragging on the canvas after saving.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Caption background'),
                    value: _background,
                    onChanged: (v) => setState(() => _background = v),
                  ),
                  Text(
                    'Visible from ${_start.toStringAsFixed(1)}s to ${_end.toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 12),
                  ),
                  RangeSlider(
                    values: RangeValues(_start, _end),
                    min: 0,
                    max: widget.duration,
                    onChanged: (v) => setState(() {
                      _start = v.start;
                      _end = v.end;
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) => Row(
    children: [
      SizedBox(
        width: 130,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          onChanged: (v) => setState(() => change(v)),
        ),
      ),
    ],
  );
}
