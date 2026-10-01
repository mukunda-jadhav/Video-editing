import 'package:flutter/services.dart';

/// Owned Android boundary: MediaStore export, storage checks and local ONNX.
class NativeMediaService {
  const NativeMediaService();
  static const channel = MethodChannel('com.framelab/media');
  Future<int> availableBytes() async =>
      await channel.invokeMethod<int>('availableBytes') ?? 0;
  Future<String> removeBackground(String sourcePath) async {
    final result = await channel.invokeMethod<String>('removeBackground', {
      'path': sourcePath,
    });
    if (result == null) {
      throw StateError('Background removal produced no output.');
    }
    return result;
  }

  Future<void> cancelBackgroundRemoval() =>
      channel.invokeMethod<void>('cancelBackgroundRemoval');

  /// Processes at most one small frame batch on the Android worker. ONNX stays
  /// local; the native implementation reuses a session and recycles each frame.
  Future<void> processVideoCutoutFrames(
    String directory, {
    required bool automatic,
    required int backgroundColor,
    String? backgroundPath,
    List<Map<String, dynamic>> strokes = const [],
  }) async {
    await channel.invokeMethod<String>('processVideoCutoutFrames', {
      'path': directory,
      'automatic': automatic,
      'backgroundColor': backgroundColor,
      'backgroundPath': backgroundPath,
      'strokes': strokes,
    });
  }

  /// A small, rotation-correct frame cached privately on Android. Extraction
  /// stays on the native worker; failures can leave a filmstrip placeholder.
  Future<String> getVideoThumbnail(
    String path, {
    double timeSeconds = 0,
  }) async {
    if (!timeSeconds.isFinite || timeSeconds < 0) {
      throw ArgumentError.value(
        timeSeconds,
        'timeSeconds',
        'Use a non-negative finite time.',
      );
    }
    final result = await channel.invokeMethod<String>('getVideoThumbnail', {
      'path': path,
      'timeSeconds': timeSeconds,
    });
    if (result == null || result.isEmpty) {
      throw StateError('This clip has no decodable preview frame.');
    }
    return result;
  }

  Future<String> publish(
    String path,
    String name, {
    required bool video,
  }) async {
    final result = await channel.invokeMethod<String>('publish', {
      'path': path,
      'name': name,
      'video': video,
    });
    if (result == null) throw StateError('Android did not create an export.');
    return result;
  }

  Future<Map<String, dynamic>> diagnostics() async => Map<String, dynamic>.from(
    await channel.invokeMapMethod<String, dynamic>('diagnostics') ?? {},
  );
}
