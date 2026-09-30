import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
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
    try {
      final path = await widget.pickImage();
      if (path != null && mounted) {
        _change(
          _document.copyWith(
            overlay: VideoOverlay(path: path, end: _document.duration),
          ),
        );
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
      final frameWidth = constraints.maxWidth;
      final frameHeight = constraints.maxHeight;
      final source = player.value.size;
      final scale =
          math.max(frameWidth / source.width, frameHeight / source.height) *
          clip.zoom;
      final width = source.width * scale;
      final height = source.height * scale;
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
      final videoTexture = Positioned(
        key: const ValueKey('video-live-crop'),
        left: -(width - frameWidth) * clip.cropX,
        top: -(height - frameHeight) * clip.cropY,
        width: width,
        height: height,
        child: video,
      );
      return ClipRect(
        child: ValueListenableBuilder<double>(
          valueListenable: _position,
          child: videoTexture,
          builder: (context, position, texture) {
            final local =
                (position - VideoPreviewPosition.startOf(_document, _selected))
                    .clamp(0, clip.duration);
            final fadeTime = math.min(.4, clip.duration / 3);
            final opacity = clip.effect == VideoEffect.fade
                ? math
                      .min(local / fadeTime, (clip.duration - local) / fadeTime)
                      .clamp(0, 1)
                      .toDouble()
                : 1.0;
            final overlay = _document.overlay;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: opacity,
                    child: Stack(children: [texture!]),
                  ),
                ),
                if (clip.effect == VideoEffect.vignette ||
                    clip.filter == VideoFilter.cinema)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: .5),
                            ],
                            stops: const [.35, 1.0],
                            radius: .8,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (overlay != null &&
                    position >= overlay.start &&
                    position <= overlay.end)
                  Align(
                    alignment: Alignment(overlay.x * 2 - 1, overlay.y * 2 - 1),
                    child: Opacity(
                      opacity: overlay.opacity,
                      child: SizedBox(
                        width: frameWidth * overlay.width,
                        child: Image.file(
                          File(overlay.path),
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                for (final text in _document.texts)
                  if (position >= text.start && position <= text.end)
                    Align(
                      alignment: Alignment(text.x * 2 - 1, text.y * 2 - 1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: text.background
                              ? Colors.black.withValues(alpha: .55)
                              : Colors.transparent,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(text.background ? 4 : 0),
                          child: Text(
                            text.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: text.font,
                              fontSize: math.max(8, frameHeight * text.size),
                              color: Color(text.color),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      );
    },
  );

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
            onTap: () => setState(() => _tool = tool.$1),
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
              Text(
                '${_selected + 1}/${_document.clips.length}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...switch (_tool) {
            'Trim' => _trimTools(clip),
            'Canvas' => _canvasTools(clip),
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
    _slider(
      'Zoom • ${clip.zoom.toStringAsFixed(2)}×',
      clip.zoom,
      1,
      3,
      (v) => _editClip(clip.copyWith(zoom: v), commit: false),
    ),
    _slider(
      'Crop horizontal',
      clip.cropX,
      0,
      1,
      (v) => _editClip(clip.copyWith(cropX: v), commit: false),
    ),
    _slider(
      'Crop vertical',
      clip.cropY,
      0,
      1,
      (v) => _editClip(clip.copyWith(cropY: v), commit: false),
    ),
    const Text(
      'The frame fills the chosen canvas. Use position and zoom to keep your subject in view.',
      style: TextStyle(fontSize: 11),
    ),
  ];

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
    const Text('Color the selected clip', style: TextStyle(fontSize: 12)),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: VideoFilter.values
          .map(
            (filter) => ChoiceChip(
              label: Text(_label(filter.name)),
              selected: clip.filter == filter,
              onSelected: (_) async {
                if (mounted) _editClip(_clip!.copyWith(filter: filter));
              },
            ),
          )
          .toList(),
    ),
    const SizedBox(height: 12),
    const Text(
      'Color changes are live. Use composition preview to check the final look.',
      style: TextStyle(fontSize: 11),
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
            VideoText(id: _id(), text: 'Your story', end: _document.duration),
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
  }

  List<Widget> _overlayTools() {
    final overlay = _document.overlay;
    return [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickOverlay,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                overlay == null ? 'Add image overlay' : 'Replace image',
              ),
            ),
          ),
          if (overlay != null)
            IconButton(
              tooltip: 'Remove overlay',
              onPressed: () => _change(_document.copyWith(removeOverlay: true)),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      if (overlay != null) ...[
        _slider('Size', overlay.width, .05, 1, (v) => _updateOverlay(width: v)),
        _slider(
          'Opacity',
          overlay.opacity,
          0,
          1,
          (v) => _updateOverlay(opacity: v),
        ),
        _slider(
          'Horizontal position',
          overlay.x,
          0,
          1,
          (v) => _updateOverlay(x: v),
        ),
        _slider(
          'Vertical position',
          overlay.y,
          0,
          1,
          (v) => _updateOverlay(y: v),
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
            'Layer a logo, sticker or photo. Transparent PNG images keep their transparency.',
            style: TextStyle(fontSize: 12),
          ),
        ),
    ];
  }

  void _updateOverlay({
    double? width,
    double? opacity,
    double? x,
    double? y,
    double? start,
    double? end,
  }) {
    final overlay = _document.overlay!;
    _change(
      _document.copyWith(
        overlay: VideoOverlay(
          path: overlay.path,
          width: width ?? overlay.width,
          opacity: opacity ?? overlay.opacity,
          x: x ?? overlay.x,
          y: y ?? overlay.y,
          start: start ?? overlay.start,
          end: end ?? overlay.end,
        ),
      ),
      commit: false,
    );
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
                  _slider('Font size', _size, .02, .25, (v) => _size = v),
                  _slider('Horizontal position', _x, 0, 1, (v) => _x = v),
                  _slider('Vertical position', _y, 0, 1, (v) => _y = v),
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
