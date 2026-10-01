import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/video_editor/data/video_cutout_service.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';

void main() {
  const original = VideoClip(
    id: 'source',
    path: 'original.mp4',
    sourceDuration: 20,
    start: 10,
    end: 12,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );
  test('unprocessed clip keeps its original source without a copy', () {
    expect(identical(VideoCutoutService.originalFor(original), original), true);
  });
  test(
    'reopening trimmed cutout maps back to original and preserves current edits',
    () {
      final baked = original.copyWith(
        path: 'baked.mp4',
        start: .25,
        end: 1.5,
        sourceDuration: 2,
        width: 1280,
        height: 720,
        cutoutOriginal: original,
        speed: 1.5,
        volume: .2,
        filter: VideoFilter.warm,
        filterIntensity: .4,
        positionX: .2,
        positionY: -.1,
        fit: VideoFit.fit,
        cutoutRecipe: {
          'automatic': false,
          'backgroundColor': 0xff000000,
          'strokes': <Map<String, dynamic>>[],
        },
      );
      final reopened = VideoCutoutService.originalFor(
        VideoClip.fromJson(baked.toJson()),
      );
      expect(reopened.path, 'original.mp4');
      expect(reopened.start, 10.25);
      expect(reopened.end, 11.5);
      expect(reopened.sourceDuration, 20);
      expect([reopened.width, reopened.height], [1920, 1080]);
      expect(reopened.speed, 1.5);
      expect(reopened.volume, .2);
      expect(reopened.filterIntensity, .4);
      expect(reopened.positionX, .2);
      expect(reopened.positionY, -.1);
      expect(reopened.fit, VideoFit.fit);
      expect(reopened.cutoutOriginal, isNull);
      expect(reopened.cutoutRecipe, isNull);
    },
  );
  test('rounded encoded duration cannot read beyond original trim end', () {
    final baked = original.copyWith(
      path: 'baked.mp4',
      start: 0,
      end: 2.033,
      sourceDuration: 2.033,
      cutoutOriginal: original,
    );
    expect(VideoCutoutService.originalFor(baked).end, 12);
  });
}
