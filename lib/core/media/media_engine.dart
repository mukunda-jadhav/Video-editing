enum ExportResolution { hd720, fullHd1080, ultraHd4k }

enum MediaKind { photo, video }

class MediaSource {
  MediaSource({required this.uri, required this.kind}) {
    final localFile =
        uri.scheme == 'file' &&
        (uri.authority.isEmpty || uri.authority == 'localhost') &&
        uri.path.startsWith('/') &&
        uri.path.length > 1;
    final androidContent =
        uri.scheme == 'content' &&
        uri.authority.isNotEmpty &&
        uri.path.startsWith('/') &&
        uri.path.length > 1;
    if ((!localFile && !androidContent) || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Only local file/content URIs are allowed',
      );
    }
  }
  final Uri uri;
  final MediaKind kind;
}

class EngineCapabilities {
  EngineCapabilities({
    required Set<ExportResolution> resolutions,
    required this.supportsTransitions,
  }) : resolutions = Set.unmodifiable(resolutions);
  final Set<ExportResolution> resolutions;
  final bool supportsTransitions;
}

/// Pass job IDs/URIs across native channels rather than copying decoded frames.
abstract interface class ExportJob {
  Stream<double> get progress;
  Future<Uri> get result;
  Future<void> cancel();
}

/// Capability contract for additional native rendering backends.
abstract interface class MediaEngine {
  Future<EngineCapabilities> capabilities();
  Future<void> dispose();
}

/// On-device inference produces a local alpha mask, never a remote URL.
abstract interface class BackgroundRemovalEngine {
  Future<Uri> createMask(MediaSource source);
  Future<void> dispose();
}
