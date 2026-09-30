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
