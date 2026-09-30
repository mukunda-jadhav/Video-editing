enum ProjectKind { photo, video, design }

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.title,
    required this.kind,
    required this.updatedAt,
    this.thumbnailPath,
  });
  final String id;
  final String title;
  final ProjectKind kind;
  final DateTime updatedAt;
  final String? thumbnailPath;
}

/// Metadata only; media buffers never enter UI state. ProjectStore extends
/// this contract with versioned documents and atomic save operations.
abstract interface class ProjectRepository {
  Future<List<ProjectSummary>> listRecent();
}
