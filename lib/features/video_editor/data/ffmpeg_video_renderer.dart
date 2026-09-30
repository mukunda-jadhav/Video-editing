import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/video_document.dart';
import '../domain/video_render_plan.dart';
import '../domain/video_renderer.dart';

/// Sequential normalization and pairwise composition keep only two video
/// decoders alive. No raw frames cross Flutter's platform channel. Each job
/// owns an isolated temporary directory; cancellations remove partial output.
class FfmpegVideoRenderer implements VideoRenderer {
  FfmpegVideoRenderer({this.preferredEncoder = 'h264_mediacodec'});
  final String preferredEncoder;
  int? _session;
  bool _cancelled = false;
  bool _busy = false;
  bool _disposed = false;
  final Map<String, Directory> _completed = {};

  Future<void> _checkFile(String path) async {
    if (path.contains('\u0000') ||
        !File(path).isAbsolute ||
        !await File(path).exists()) {
      throw FileSystemException(
        'The original media is missing. Import it again.',
        path,
      );
    }
  }

  @override
  Future<VideoClip> probe(String path) async {
    await _checkFile(path);
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    final video = info
        ?.getStreams()
        .where((s) => s.getType() == 'video')
        .firstOrNull;
    final duration = double.tryParse(info?.getDuration() ?? '') ?? 0;
    if (video == null || !duration.isFinite || duration < .05) {
      throw const FormatException(
        'This file does not contain a readable video. Try an MP4 or MOV file.',
      );
    }
    var width = video.getWidth() ?? 0;
    var height = video.getHeight() ?? 0;
    final properties = video.getAllProperties();
    final sides = properties?['side_data_list'];
    if (sides is List) {
      for (final dynamic side in sides) {
        if (side is Map &&
            side['rotation'] is num &&
            (side['rotation'] as num).abs() % 180 == 90) {
          final oldWidth = width;
          width = height;
          height = oldWidth;
          break;
        }
      }
    }
    if (width <= 0 || height <= 0) {
      throw const FormatException('The video has invalid dimensions.');
    }
    return VideoClip(
      id: '${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(100000)}',
      path: path,
      sourceDuration: duration,
      end: duration,
      width: width,
      height: height,
      hasAudio: info!.getStreams().any((s) => s.getType() == 'audio'),
    );
  }

  Future<void> _execute(
    List<String> args,
    double duration,
    void Function(double) progress,
  ) async {
    if (_cancelled || _disposed) {
      throw const VideoRenderCancelled();
    }
    final done = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        try {
          final code = await session.getReturnCode();
          if (_cancelled || ReturnCode.isCancel(code)) {
            throw const VideoRenderCancelled();
          }
          if (!ReturnCode.isSuccess(code)) {
            final logs = await session.getAllLogsAsString();
            final details = logs == null
                ? 'The encoder returned no details.'
                : logs.substring(math.max(0, logs.length - 1600));
            throw StateError('Video processing failed. $details');
          }
          if (!done.isCompleted) {
            done.complete();
          }
        } catch (error, stack) {
          if (!done.isCompleted) {
            done.completeError(error, stack);
          }
        }
      },
      (_) {},
      (statistics) {
        if (!_cancelled && !_disposed) {
          progress((statistics.getTime() / (duration * 1000)).clamp(0, 1));
        }
      },
    );
    _session = session.getSessionId();
    if (_cancelled || _disposed) {
      await FFmpegKit.cancel(_session);
    }
    try {
      await done.future;
    } finally {
      _session = null;
    }
  }

  @override
  Future<VideoRenderResult> render(
    VideoDocument document, {
    required int shortEdge,
    required void Function(double progress, String stage) onProgress,
  }) async {
    if (_busy) {
      throw StateError('A video is already being rendered.');
    }
    if (_disposed) {
      throw StateError('The renderer has been closed.');
    }
    final plan = VideoRenderPlan(document, shortEdge: shortEdge);
    _busy = true;
    _cancelled = false;
    Directory? job;
    try {
      for (final clip in document.clips) {
        await _checkFile(clip.path);
      }
      if (document.musicPath != null) {
        await _checkFile(document.musicPath!);
      }
      var musicRepeats = 0;
      var musicOffset = 0.0;
      if (document.musicPath != null) {
        final session = await FFprobeKit.getMediaInformation(
          document.musicPath!,
        );
        final information = session.getMediaInformation();
        final length = double.tryParse(information?.getDuration() ?? '') ?? 0;
        if (!length.isFinite ||
            length < .05 ||
            !(information?.getStreams().any(
                  (stream) => stream.getType() == 'audio',
                ) ??
                false)) {
          throw const FormatException(
            'Choose a readable music track with audio.',
          );
        }
        // An infinite stream_loop can keep FFmpeg's input worker alive after
        // the MP4 is finalized. A finite repeat count still fills the timeline.
        // Wrap seeks beyond the song's end into the repeated music cycle.
        musicOffset = document.musicStart % length;
        musicRepeats = math.max(
          0,
          ((document.duration + musicOffset) / length).ceil() - 1,
        );
      }
      if (document.overlay != null) {
        await _checkFile(document.overlay!.path);
      }
      // Do not retain unbounded logs/statistics across rendering many clips.
      await FFmpegKitConfig.setSessionHistorySize(8);
      final temp = await getTemporaryDirectory();
      job = await Directory('${temp.path}/video_jobs').create(recursive: true);
      job = await job.createTemp('render_');
      var stage = 0;
      final stages =
          document.clips.length * 2 + (document.musicPath == null ? 0 : 1);
      void report(double value, String label) {
        if (!_disposed) {
          onProgress(((stage + value) / stages).clamp(0, .999), label);
        }
      }

      String? preparedMusic;
      if (document.musicPath != null) {
        preparedMusic = '${job.path}/music.wav';
        await _execute(
          plan.prepareMusic(
            output: preparedMusic,
            repeats: musicRepeats,
            offset: musicOffset,
          ),
          document.duration,
          (p) => report(p, 'Preparing music'),
        );
        stage++;
      }

      var current = '';
      var currentDuration = 0.0;
      for (var index = 0; index < document.clips.length; index++) {
        final clip = document.clips[index];
        final normalized = '${job.path}/clip_$index.mp4';
        await _execute(
          plan.normalize(clip, normalized),
          clip.duration,
          (p) => report(
            p,
            'Processing clip ${index + 1} of ${document.clips.length}',
          ),
        );
        stage++;
        if (index == 0) {
          current = normalized;
          currentDuration = clip.duration;
        } else {
          final stitched = '${job.path}/sequence_$index.mp4';
          final nextDuration =
              currentDuration +
              clip.duration -
              document.transitionAt(index - 1);
          await _execute(
            plan.stitch(
              left: current,
              right: normalized,
              output: stitched,
              leftDuration: currentDuration,
              boundary: index - 1,
            ),
            nextDuration,
            (p) => report(p, 'Joining clips $index and ${index + 1}'),
          );
          stage++;
          await File(current).delete();
          await File(normalized).delete();
          current = stitched;
          currentDuration = nextDuration;
        }
      }
      final textFiles = <String, String>{};
      final fontFiles = <String, String>{};
      for (var i = 0; i < document.texts.length; i++) {
        final text = document.texts[i];
        final path = '${job.path}/text_$i.txt';
        await File(path).writeAsString(text.text, flush: true);
        textFiles[text.id] = path;
        if (!fontFiles.containsKey(text.font)) {
          final fontPath = '${job.path}/${text.font}.ttf';
          final font = await rootBundle.load('assets/fonts/${text.font}.ttf');
          await File(fontPath).writeAsBytes(
            font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
            flush: true,
          );
          fontFiles[text.font] = fontPath;
        }
      }
      final output = '${job.path}/export.mp4';
      Future<void> verifyOutput() async {
        if (_cancelled || _disposed) {
          throw const VideoRenderCancelled();
        }
        if (!await File(output).exists() || await File(output).length() < 256) {
          throw StateError('The output file is empty.');
        }
        // Some Android hardware encoders report success but emit no video.
        // Probe the actual output before accepting either encoder attempt.
        final verified = await probe(output);
        if (!verified.hasAudio ||
            verified.width != plan.width ||
            verified.height != plan.height ||
            (verified.sourceDuration - document.duration).abs() >
                math.max(.3, document.clips.length / 30)) {
          throw StateError(
            'The encoded video did not match the requested timeline.',
          );
        }
      }

      var codec = preferredEncoder;
      try {
        await _execute(
          plan.finish(
            input: current,
            output: output,
            textFiles: textFiles,
            fontFiles: fontFiles,
            encoder: codec,
            preparedMusic: preparedMusic,
          ),
          document.duration,
          (p) => report(p, 'Encoding final video'),
        );
        await verifyOutput();
      } on VideoRenderCancelled {
        rethrow;
      } catch (_) {
        if (codec == 'mpeg4') {
          rethrow;
        }
        codec = 'mpeg4';
        await _execute(
          plan.finish(
            input: current,
            output: output,
            textFiles: textFiles,
            fontFiles: fontFiles,
            encoder: codec,
            preparedMusic: preparedMusic,
          ),
          document.duration,
          (p) => report(p, 'Using compatible software encoder'),
        );
        await verifyOutput();
      }
      if (_cancelled || _disposed) {
        throw const VideoRenderCancelled();
      }
      await File(current).delete();
      _completed[output] = job;
      onProgress(1, 'Video ready');
      return VideoRenderResult(
        path: output,
        codec: codec == 'mpeg4' ? 'MPEG-4 (software)' : 'H.264',
        width: plan.width,
        height: plan.height,
      );
    } catch (_) {
      if (job != null && await job.exists()) {
        await job.delete(recursive: true);
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final session = _session;
    if (session != null) {
      await FFmpegKit.cancel(session);
    }
  }

  @override
  Future<void> release(String path) async {
    final directory = _completed.remove(path);
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await cancel();
    for (final path in _completed.keys.toList()) {
      await release(path);
    }
  }
}
