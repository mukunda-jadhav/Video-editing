import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../features/photo_editor/presentation/photo_editor_screen.dart';
import '../features/photo_editor/domain/photo_document.dart';
import '../features/video_editor/presentation/video_editor_screen.dart';
import '../features/video_editor/domain/video_document.dart';
import '../features/projects/domain/project_document.dart';
import '../features/projects/domain/project_repository.dart';
import '../features/templates/domain/template_catalog.dart';
import 'providers.dart';

class EditorHost extends ConsumerStatefulWidget {
  const EditorHost({
    super.key,
    this.video = false,
    this.projectId,
    this.templateId,
  });
  final bool video;
  final String? projectId, templateId;
  @override
  ConsumerState<EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends ConsumerState<EditorHost> {
  late final String _id =
      widget.projectId ??
      'p${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
  late Future<Map<String, dynamic>?> _loadFuture;
  late final ProjectStore _store;
  ProjectDocument? _previous;
  StudioTemplate? _template;
  bool _video = false;
  List<String> _missing = [];
  bool _relinking = false;
  @override
  void initState() {
    super.initState();
    _store = ref.read(projectStoreProvider);
    _loadFuture = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    _video = widget.video;
    if (widget.projectId != null) {
      _previous = await _store.load(_id);
      if (_previous == null) {
        throw const FileSystemException('This project no longer exists.');
      }
      _video = _previous!.kind == ProjectKind.video;
      // Validate before mounting an editor so damaged or newer recipes show
      // the recoverable project error screen and cannot be auto-overwritten.
      if (_video) {
        VideoDocument.fromJson(_previous!.recipe);
      } else {
        PhotoDocument.fromJson(_previous!.recipe);
      }
      _template = templateCatalog
          .where((t) => t.id == _previous!.recipe['_templateId'])
          .firstOrNull;
      final paths = _mediaPaths(_previous!.recipe).toSet();
      _missing = [];
      for (final path in paths) {
        if (!await File(path).exists()) _missing.add(path);
      }
      return _previous!.recipe;
    }
    if (widget.templateId != null) {
      _template = templateCatalog
          .where((t) => t.id == widget.templateId)
          .firstOrNull;
      if (_template == null) throw const FormatException('Template not found.');
      _video = _template!.video;
      return _template!.createRecipe();
    }
    return null;
  }

  Iterable<String> _mediaPaths(Object? value) sync* {
    if (value is Map) {
      for (final entry in value.entries) {
        if (const [
              'path',
              'imagePath',
              'backgroundPath',
              'musicPath',
            ].contains(entry.key) &&
            entry.value is String &&
            (entry.value as String).isNotEmpty) {
          yield entry.value as String;
        } else {
          yield* _mediaPaths(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        yield* _mediaPaths(item);
      }
    }
  }

  Future<void> _save(
    Map<String, dynamic> recipe,
    String title,
    String? thumbnail,
  ) async {
    final data = Map<String, dynamic>.from(recipe);
    if (_template != null) data['_templateId'] = _template!.id;
    String? stableThumbnail = _previous?.thumbnailPath;
    if (thumbnail != null && await File(thumbnail).exists()) {
      final folder = await _store.assetsDirectory(_id);
      final target = p.join(folder, 'thumbnail.png');
      if (p.normalize(thumbnail) != p.normalize(target)) {
        await File(thumbnail).copy(target);
      }
      stableThumbnail = target;
    }
    final now = DateTime.now().toUtc();
    final document = ProjectDocument(
      id: _id,
      kind: _video
          ? ProjectKind.video
          : _template != null
          ? ProjectKind.design
          : ProjectKind.photo,
      title: title.trim().isEmpty
          ? 'Untitled project'
          : title.trim().substring(0, min(200, title.trim().length)),
      createdAt: _previous?.createdAt ?? now,
      updatedAt: now,
      recipe: data,
      thumbnailPath: stableThumbnail,
    );
    await _store.save(document);
    _previous = document;
    if (mounted) ref.invalidate(recentProjectsProvider);
  }

  Future<List<String>> _pick(FileType type, {bool multiple = false}) =>
      ref.read(mediaImportServiceProvider).pick(_id, type, multiple: multiple);
  Future<String?> _pickImage() async =>
      (await _pick(FileType.image)).firstOrNull;
  Future<String> _exportImage(Uint8List bytes, String name) async {
    final temp = await getTemporaryDirectory();
    final file = File(
      p.join(
        temp.path,
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(name)}',
      ),
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await ref
          .read(nativeMediaServiceProvider)
          .publish(file.path, name, video: false);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _relink(String missing) async {
    setState(() => _relinking = true);
    try {
      final replacement = (await _pick(FileType.any)).firstOrNull;
      if (replacement == null || _previous == null) return;
      Object? replace(Object? value) {
        if (value == missing) return replacement;
        if (value is Map) {
          return value.map(
            (key, value) => MapEntry(key.toString(), replace(value)),
          );
        }
        if (value is List) return value.map(replace).toList();
        return value;
      }

      final recipe = replace(_previous!.recipe) as Map<String, dynamic>;
      await _save(recipe, _previous!.title, _previous!.thumbnailPath);
      if (mounted) setState(() => _loadFuture = _load());
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not relink media: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _relinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Project unavailable')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('${snapshot.error}'),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => setState(() => _loadFuture = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (_missing.isNotEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Relink missing media')),
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Your edit recipe is safe. Select a replacement for each missing file to continue.',
                ),
                const SizedBox(height: 16),
                for (final path in _missing)
                  Card(
                    child: ListTile(
                      title: Text(p.basename(path)),
                      subtitle: const Text('File unavailable'),
                      trailing: TextButton(
                        onPressed: _relinking ? null : () => _relink(path),
                        child: const Text('Relink'),
                      ),
                    ),
                  ),
                if (_relinking) const LinearProgressIndicator(),
              ],
            ),
          );
        }
        if (_video) {
          return VideoEditorScreen(
            initialData: snapshot.data,
            onSave: _save,
            thumbnailLoader: (path, seconds) => ref
                .read(nativeMediaServiceProvider)
                .getVideoThumbnail(path, timeSeconds: seconds),
            pickVideos: () => _pick(FileType.video, multiple: true),
            pickAudio: () async => (await _pick(FileType.audio)).firstOrNull,
            pickImage: _pickImage,
            publishVideo: (path, name) async {
              return ref
                  .read(nativeMediaServiceProvider)
                  .publish(path, name, video: true);
            },
          );
        }
        return PhotoEditorScreen(
          initialData: snapshot.data,
          onSave: _save,
          removeBackground: (path) async {
            return ref.read(nativeMediaServiceProvider).removeBackground(path);
          },
          exportBytes: _exportImage,
          pickImage: _pickImage,
        );
      },
    );
  }
}
