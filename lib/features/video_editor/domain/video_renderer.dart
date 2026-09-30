import 'video_document.dart';

class VideoRenderResult {
  const VideoRenderResult({
    required this.path,
    required this.codec,
    required this.width,
    required this.height,
  });
  final String path;
  final String codec;
  final int width;
  final int height;
}

class VideoRenderCancelled implements Exception {
  const VideoRenderCancelled();
  @override
  String toString() => 'Rendering cancelled.';
}

abstract interface class VideoRenderer {
  Future<VideoClip> probe(String path);
  Future<VideoRenderResult> render(
    VideoDocument document, {
    required int shortEdge,
    required void Function(double progress, String stage) onProgress,
  });
  Future<void> cancel();
  Future<void> release(String path);
  Future<void> dispose();
}
