import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/media/native_media_service.dart';
import '../domain/video_document.dart';

class VideoCutoutCancelled implements Exception {
  const VideoCutoutCancelled();
  @override
  String toString() => 'Background removal cancelled.';
}

/// On-device video segmentation. One-second batches bound temporary frame
/// storage and native memory; no entire-video bitmap list is retained.
/// Brush strokes are stationary source-coordinate corrections across the clip.
class VideoCutoutService {
  VideoCutoutService({this.native = const NativeMediaService()});
  final NativeMediaService native;

  /// Map trims on a baked cutout back to the retained original source. Current
  /// visual/audio edits survive; processing never segments a replacement image.
  static VideoClip originalFor(VideoClip clip) {
    final original = clip.cutoutOriginal;
    if (original == null) return clip;
    return clip.copyWith(
      path: original.path,
      start: original.start + clip.start,
      end: math.min(original.end, original.start + clip.end),
      sourceDuration: original.sourceDuration,
      width: original.width,
      height: original.height,
      hasAudio: original.hasAudio,
      clearCutoutOriginal: true,
    );
  }

  bool _cancelled = false;
  int? _sessionId;
  Directory? _previewDirectory;

  void _checkCancelled() {
    if (_cancelled) throw const VideoCutoutCancelled();
  }

  /// UI calls this only after the prior awaited operation has settled.
  void resetForRetry() {
    if (_sessionId != null) {
      throw StateError('The prior operation is still running.');
    }
    _cancelled = false;
  }

  Future<void> cancel() async {
    _cancelled = true;
    final session = _sessionId;
    await Future.wait([
      native.cancelBackgroundRemoval(),
      if (session != null) FFmpegKit.cancel(session),
    ]);
  }

  Future<void> _execute(List<String> arguments) async {
    _checkCancelled();
    final complete = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(arguments, (
      s,
    ) async {
      try {
        final code = await s.getReturnCode();
        if (_cancelled || ReturnCode.isCancel(code)) {
          throw const VideoCutoutCancelled();
        }
        if (!ReturnCode.isSuccess(code)) {
          throw const FormatException(
            'This video could not be processed. The original clip is unchanged.',
          );
        }
        complete.complete();
      } catch (e, stack) {
        complete.completeError(e, stack);
      }
    });
    _sessionId = session.getSessionId();
    if (_cancelled) await FFmpegKit.cancel(_sessionId);
    try {
      await complete.future;
    } finally {
      _sessionId = null;
    }
  }

  static const _scale =
      "scale=w='min(iw,1920)':h='min(ih,1920)':force_original_aspect_ratio=decrease:force_divisible_by=2";

  Future<String> previewFrame(VideoClip clip) async {
    _checkCancelled();
    final support = await getApplicationSupportDirectory();
    final directory = await Directory(
      p.join(support.path, 'cutout_preview'),
    ).create(recursive: true);
    _previewDirectory = await directory.createTemp('frame_');
    final frame = p.join(_previewDirectory!.path, 'original.png');
    await _execute([
      '-y',
      '-ss',
      clip.start.toStringAsFixed(6),
      '-i',
      clip.path,
      '-vf',
      _scale,
      '-frames:v',
      '1',
      '-an',
      frame,
    ]);
    if (!await File(frame).exists()) {
      throw const FormatException('This clip has no readable preview frame.');
    }
    return frame;
  }

  Future<String> autoPreview(String frame) async {
    _checkCancelled();
    final output = await native.removeBackground(frame);
    _checkCancelled();
    return output;
  }

  Future<String> process(
    VideoClip clip, {
    required bool automatic,
    required int backgroundColor,
    String? backgroundPath,
    List<Map<String, dynamic>> strokes = const [],
    required void Function(double value, String stage) onProgress,
  }) async {
    _checkCancelled();
    if (!automatic && strokes.isEmpty) {
      throw const FormatException(
        'Erase an area manually, or enable automatic removal.',
      );
    }
    final duration = clip.end - clip.start;
    if (!duration.isFinite ||
        duration < .04 ||
        !await File(clip.path).exists()) {
      throw const FormatException('The original video is unavailable.');
    }
    final available = await native.availableBytes();
    const reserve = 64 * 1024 * 1024;
    final sourceScale = math.min(1.0, 1920 / math.max(clip.width, clip.height));
    final frameBytes =
        (clip.width * clip.height * sourceScale * sourceScale * 5).ceil();
    final frameBudget = math.min(128 * 1024 * 1024, available - reserve);
    if (frameBudget < frameBytes) {
      throw const FileSystemException(
        'Free more storage for video background removal.',
      );
    }
    final batchFrames = (frameBudget / frameBytes).floor().clamp(1, 30);
    final support = await getApplicationSupportDirectory();
    final base = await Directory(
      p.join(support.path, 'video_cutouts'),
    ).create(recursive: true);
    final work = await base.createTemp('work_');
    final output = p.join(
      base.path,
      'cutout_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    final segments = <String>[];
    var success = false;
    try {
      final frameDirectory = await Directory(
        p.join(work.path, 'frames'),
      ).create();
      final totalFrames = math.max(1, (duration * 30).ceil());
      final chunks = (totalFrames / batchFrames).ceil();
      for (var chunk = 0; chunk < chunks; chunk++) {
        _checkCancelled();
        if (await native.availableBytes() <
            reserve + frameBytes * batchFrames) {
          throw const FileSystemException(
            'Storage is running low. The original video is safe.',
          );
        }
        final frames = math.min(batchFrames, totalFrames - chunk * batchFrames);
        onProgress(chunk / chunks * .94, 'Reading frames ${chunk + 1}/$chunks');
        final pattern = p.join(frameDirectory.path, '%06d.png');
        await _execute([
          '-y',
          '-ss',
          (clip.start + chunk * batchFrames / 30).toStringAsFixed(6),
          '-i',
          clip.path,
          '-t',
          math
              .min(batchFrames / 30, duration - chunk * batchFrames / 30)
              .toStringAsFixed(6),
          '-vf',
          'fps=30,$_scale',
          '-frames:v',
          frames.toString(),
          '-an',
          pattern,
        ]);
        _checkCancelled();
        onProgress(
          (chunk + .25) / chunks * .94,
          automatic ? 'Removing background on-device' : 'Applying manual mask',
        );
        await native.processVideoCutoutFrames(
          frameDirectory.path,
          automatic: automatic,
          backgroundColor: backgroundColor,
          backgroundPath: backgroundPath,
          strokes: strokes,
        );
        _checkCancelled();
        final segment = p.join(
          work.path,
          'segment_${chunk.toString().padLeft(5, '0')}.mp4',
        );
        onProgress((chunk + .8) / chunks * .94, 'Encoding processed frames');
        await _execute([
          '-y',
          '-framerate',
          '30',
          '-i',
          pattern,
          '-an',
          '-c:v',
          'mpeg4',
          '-q:v',
          '3',
          '-pix_fmt',
          'yuv420p',
          segment,
        ]);
        segments.add(segment);
        await for (final file in frameDirectory.list()) {
          if (file is File) await file.delete();
        }
      }
      _checkCancelled();
      final list = File(p.join(work.path, 'segments.txt'));
      await list.writeAsString(
        segments
            .map((path) => "file '${path.replaceAll("'", "'\\''")}'")
            .join('\n'),
      );
      onProgress(.95, 'Finishing video and preserving audio');
      await _execute([
        '-y',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        list.path,
        '-ss',
        clip.start.toStringAsFixed(6),
        '-i',
        clip.path,
        '-map',
        '0:v:0',
        '-map',
        '1:a:0?',
        '-t',
        duration.toStringAsFixed(6),
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        '-b:a',
        '160k',
        '-movflags',
        '+faststart',
        output,
      ]);
      _checkCancelled();
      success = true;
      onProgress(1, 'Background removed');
      return output;
    } finally {
      await work.delete(recursive: true);
      if (!success && await File(output).exists()) await File(output).delete();
    }
  }

  Future<void> dispose() async {
    await cancel();
    final preview = _previewDirectory;
    if (preview != null && await preview.exists()) {
      await preview.delete(recursive: true);
    }
  }
}
