import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_realtime_preview.dart';
import 'package:framelab/features/video_editor/domain/video_render_plan.dart';

void main() {
  test(
    'source mapping applies trim, speed and transition overlap when scrubbing',
    () {
      final document = VideoDocument(
        clips: const [
          VideoClip(
            id: 'a',
            path: '/a.mp4',
            sourceDuration: 10,
            start: 2,
            end: 8,
            speed: 2,
            transition: VideoTransition.dissolve,
            transitionDuration: .5,
          ),
          VideoClip(
            id: 'b',
            path: '/b.mp4',
            sourceDuration: 10,
            start: 1,
            end: 5,
            speed: .5,
          ),
        ],
      );
      final first = VideoPreviewPosition.at(document, 1.25);
      expect(first.index, 0);
      expect(first.sourceSeconds, 4.5);
      expect(VideoPreviewPosition.startOf(document, 1), 2.5);
      final second = VideoPreviewPosition.at(document, 3.5);
      expect(second.index, 1);
      expect(second.sourceSeconds, 1.5);
      expect(VideoPreviewPosition.at(document, 999).sourceSeconds, 5);
    },
  );
  test(
    'brightness adjustment changes GPU colors and persists to final export plan',
    () {
      const clip = VideoClip(
        id: 'a',
        path: '/a.mp4',
        sourceDuration: 8,
        end: 8,
        brightness: .25,
        contrast: 1.2,
        saturation: .8,
        exposure: 1,
      );
      final restored = VideoClip.fromJson(clip.toJson());
      final matrix = VideoPreviewColor.matrix(restored);
      expect(matrix, hasLength(20));
      expect(matrix.every((v) => v.isFinite), isTrue);
      expect(matrix[4], closeTo(128 * -.2 * 2 + .25 * 255, .0001));
      final graph = VideoRenderPlan(
        VideoDocument(clips: [restored]),
        shortEdge: 1080,
      ).normalize(restored, '/out.mp4').join(' ');
      expect(graph, contains('hue=s=0.800000'));
      expect(graph, contains('val*2.400000+12.550000'));
      expect(restored.brightness, .25);
    },
  );
  test('old saved recipes retain neutral adjustments', () {
    const clip = VideoClip(id: 'a', path: '/a.mp4', sourceDuration: 8, end: 8);
    final old = clip.toJson()
      ..remove('brightness')
      ..remove('contrast')
      ..remove('saturation')
      ..remove('exposure');
    final restored = VideoClip.fromJson(old);
    expect(VideoPreviewColor.matrix(restored), VideoPreviewColor.identity);
    expect(VideoRenderPlan.adjustmentFor(restored), 'null');
  });
}
