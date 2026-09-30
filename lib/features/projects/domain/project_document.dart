import 'dart:convert';
import 'project_repository.dart';

/// Versioned, non-destructive recipe. Original media stays in app-private files.
class ProjectDocument {
  ProjectDocument({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required Map<String, dynamic> recipe,
    this.thumbnailPath,
  }) : recipe = Map<String, dynamic>.from(
         jsonDecode(jsonEncode(recipe)) as Map,
       );
  static const schemaVersion = 1;
  final String id;
  final ProjectKind kind;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? thumbnailPath;
  final Map<String, dynamic> recipe;
  ProjectSummary get summary => ProjectSummary(
    id: id,
    title: title,
    kind: kind,
    updatedAt: updatedAt,
    thumbnailPath: thumbnailPath,
  );
  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'kind': kind.name,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'thumbnailPath': thumbnailPath,
    'recipe': recipe,
  };
  factory ProjectDocument.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException(
        'Unsupported project version. Update FrameLab to open it.',
      );
    }
    final title = json['title'] as String;
    if (title.length > 200) {
      throw const FormatException('Invalid project title.');
    }
    return ProjectDocument(
      id: json['id'] as String,
      kind: ProjectKind.values.byName(json['kind'] as String),
      title: title,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      thumbnailPath: json['thumbnailPath'] as String?,
      recipe: Map<String, dynamic>.from(json['recipe'] as Map),
    );
  }
}

abstract interface class ProjectStore implements ProjectRepository {
  Future<ProjectDocument?> load(String id);
  Future<void> save(ProjectDocument document);
  Future<void> delete(String id);
  Future<String> assetsDirectory(String id);
}
