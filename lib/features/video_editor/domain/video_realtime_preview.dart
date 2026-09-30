import 'dart:math' as math;

import 'video_document.dart';

/// Maps an edited sequence position to its source without decoding or rendering.
/// At overlaps the quick preview cuts to the incoming clip. Full composition
/// preview and export render the exact transition and mixed audio.
class VideoPreviewPosition {
  const VideoPreviewPosition(this.index, this.sourceSeconds, this.clipSeconds);
  final int index;
  final double sourceSeconds;
  final double clipSeconds;

  static double startOf(VideoDocument document, int index) {
    var start = 0.0;
    for (var i = 0; i < index; i++) {
      start += document.clips[i].duration - document.transitionAt(i);
    }
    return start;
  }

  static VideoPreviewPosition at(VideoDocument document, double seconds) {
    if (document.clips.isEmpty) throw StateError('Add a clip first.');
    final time = seconds.clamp(0, document.duration);
    var start = 0.0;
    for (var i = 0; i < document.clips.length; i++) {
      final clip = document.clips[i];
      final next = start + clip.duration - document.transitionAt(i);
      if (time < next || i == document.clips.length - 1) {
        final local = (time - start).clamp(0, clip.duration).toDouble();
        return VideoPreviewPosition(i, clip.start + local * clip.speed, local);
      }
      start = next;
    }
    throw StateError('Invalid timeline.');
  }
}

/// Affine GPU color preview: no pixel buffers, PNG encoding, FFmpeg job, or
/// file I/O when a slider changes. YUV filtering and vignette are approximate;
/// the explicit composition preview uses the exact export processing.
abstract final class VideoPreviewColor {
  static const identity = <double>[
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  static List<double> saturation(double value) {
    final inverse = 1 - value;
    final r = .299 * inverse;
    final g = .587 * inverse;
    final b = .114 * inverse;
    return [
      r + value,
      g,
      b,
      0,
      0,
      r,
      g + value,
      b,
      0,
      0,
      r,
      g,
      b + value,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  static List<double> multiply(List<double> after, List<double> before) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 5; column++) {
        var value = column == 4 ? after[row * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          value += after[row * 5 + k] * before[k * 5 + column];
        }
        out[row * 5 + column] = value;
      }
    }
    return out;
  }

  static List<double> matrix(VideoClip clip) {
    var color = List<double>.of(identity);
    switch (clip.filter) {
      case VideoFilter.original:
        break;
      case VideoFilter.mono:
        color = saturation(0);
      case VideoFilter.vivid:
        color = multiply([
          1.08,
          0,
          0,
          0,
          -10.24,
          0,
          1.08,
          0,
          0,
          -10.24,
          0,
          0,
          1.08,
          0,
          -10.24,
          0,
          0,
          0,
          1,
          0,
        ], saturation(1.3));
      case VideoFilter.warm:
        color = [
          1.08,
          0,
          0,
          0,
          0,
          0,
          1.01,
          0,
          0,
          0,
          0,
          0,
          .9,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
      case VideoFilter.cool:
        color = [
          .9,
          0,
          0,
          0,
          0,
          0,
          1.01,
          0,
          0,
          0,
          0,
          0,
          1.1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ];
      case VideoFilter.cinema:
        color = multiply([
          1.02,
          0,
          0,
          0,
          0,
          0,
          1,
          .04,
          0,
          0,
          0,
          0,
          1.08,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ], saturation(.78));
    }
    final exposure = math.pow(2, clip.exposure).toDouble();
    final gain = clip.contrast * exposure;
    final offset = 128 * (1 - clip.contrast) * exposure + clip.brightness * 255;
    final adjustment = [
      gain,
      0.0,
      0.0,
      0.0,
      offset,
      0.0,
      gain,
      0.0,
      0.0,
      offset,
      0.0,
      0.0,
      gain,
      0.0,
      offset,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
    ];
    return multiply(adjustment, multiply(saturation(clip.saturation), color));
  }
}
