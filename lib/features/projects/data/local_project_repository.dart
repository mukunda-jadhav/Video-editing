import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../domain/project_document.dart';
import '../domain/project_repository.dart';

/// Each project is independently recoverable; an interrupted save never
/// destroys the previous recipe. JSON manifests do not contain media buffers.
class LocalProjectRepository implements ProjectStore {
  LocalProjectRepository(this.root);
  final Directory root;
  Future<void> _writes = Future.value();
  static final _validId = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');
  static const _maxMetadataBytes = 8 * 1024 * 1024;

  Directory _directory(String id) {
    if (!_validId.hasMatch(id)) throw ArgumentError('Invalid project ID');
    final target = p.normalize(p.join(root.absolute.path, id));
    if (!p.isWithin(root.absolute.path, target)) {
      throw ArgumentError('Invalid project location');
    }
    return Directory(target);
  }

  @override
  Future<String> assetsDirectory(String id) => _serialized(() async {
    final folder = Directory(p.join(_directory(id).path, 'assets'));
    await folder.create(recursive: true);
    return folder.path;
  });

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return next;
  }

  @override
  Future<void> save(ProjectDocument document) async {
    final folder = _directory(document.id);
    // Capture at submission time, before waiting on another save. Editors may
    // continue mutating their in-memory recipes while this write is queued.
    final payload = utf8.encode(jsonEncode(document.toJson()));
    if (payload.length > _maxMetadataBytes) {
      throw const FileSystemException(
        'Project recipe exceeds the safe metadata size.',
      );
    }
    await _serialized(() async {
      await folder.create(recursive: true);
      final current = File(p.join(folder.path, 'project.json'));
      final backup = File(p.join(folder.path, 'project.bak'));
      final pending = File(p.join(folder.path, 'project.pending'));
      final validCurrent = await _isRecoverable(current, document.id);

      // A recovered pending first save is still the previous committed user
      // work. Preserve it before reusing the pending file for a new write.
      if (!validCurrent &&
          !await _isRecoverable(backup, document.id) &&
          await _isRecoverable(pending, document.id)) {
        if (await backup.exists()) await backup.delete();
        await pending.rename(backup.path);
      }
      await pending.writeAsBytes(payload, flush: true);
      if (await current.exists()) {
        if (validCurrent) {
          if (await backup.exists()) await backup.delete();
          await current.rename(backup.path);
        } else {
          // Never replace a healthy recovery copy with a damaged manifest.
          await current.delete();
        }
      }
      await pending.rename(current.path);
    });
  }

  @override
  Future<ProjectDocument?> load(String id) => _serialized(() => _read(id));

  Future<ProjectDocument> _readManifest(File file, String id) async {
    if (await file.length() > _maxMetadataBytes) {
      throw const FormatException('Project metadata is too large.');
    }
    final value = ProjectDocument.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
    if (value.id != id) {
      throw const FormatException('Project ID does not match its folder.');
    }
    return value;
  }

  Future<bool> _isRecoverable(File file, String id) async {
    if (!await file.exists()) return false;
    try {
      await _readManifest(file, id);
      return true;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  Future<ProjectDocument?> _read(String id) async {
    final folder = _directory(id);
    Object? lastError;
    for (final name in ['project.json', 'project.bak', 'project.pending']) {
      final file = File(p.join(folder.path, name));
      if (!await file.exists()) continue;
      try {
        return await _readManifest(file, id);
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw FormatException('Could not recover project $id: $lastError');
    }
    return null;
  }

  @override
  Future<List<ProjectSummary>> listRecent() => _serialized(() async {
    if (!await root.exists()) {
      damagedProjectIds = const [];
      return [];
    }
    final projects = <ProjectSummary>[];
    final failures = <String>[];
    await for (final item in root.list(followLinks: false)) {
      if (item is! Directory || !_validId.hasMatch(p.basename(item.path))) {
        continue;
      }
      try {
        final value = await _read(p.basename(item.path));
        if (value != null) projects.add(value.summary);
      } on FormatException {
        failures.add(p.basename(item.path));
      }
    }
    // Keep valid projects accessible, expose corruption separately to the UI.
    damagedProjectIds = List.unmodifiable(failures);
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(projects);
  });

  List<String> damagedProjectIds = const [];

  @override
  Future<void> delete(String id) => _serialized(() async {
    final folder = _directory(id);
    if (await folder.exists()) await folder.delete(recursive: true);
  });
}
