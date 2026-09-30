import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/project_document.dart';
import '../domain/project_repository.dart';

/// Read-only empty repository for previews and isolated widget tests.
class EmptyProjectRepository implements ProjectRepository {
  const EmptyProjectRepository();
  @override
  Future<List<ProjectSummary>> listRecent() async => const [];
}

/// In-memory fallback used by widget tests and recovery screens before the
/// application support directory is available. Production startup overrides
/// this with the local disk repository.
class EphemeralProjectStore implements ProjectStore {
  EphemeralProjectStore({Directory? root})
    : _root = root ?? Directory(p.join(Directory.systemTemp.path, 'framelab'));

  final Directory _root;
  final _documents = <String, ProjectDocument>{};

  @override
  Future<List<ProjectSummary>> listRecent() async {
    final values =
        _documents.values.map((document) => document.summary).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(values);
  }

  @override
  Future<ProjectDocument?> load(String id) async => _documents[id];

  @override
  Future<void> save(ProjectDocument document) async {
    _documents[document.id] = document;
  }

  @override
  Future<void> delete(String id) async {
    _documents.remove(id);
  }

  @override
  Future<String> assetsDirectory(String id) async {
    final folder = Directory(p.join(_root.path, id, 'assets'));
    await folder.create(recursive: true);
    return folder.path;
  }
}
