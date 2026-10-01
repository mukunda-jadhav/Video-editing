import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_realtime_preview.dart';
import 'package:framelab/features/video_editor/domain/video_render_plan.dart';

const source = VideoClip(id: 'a', path: '/a.mp4', sourceDuration: 10, end: 10);
String graph(List<String> args) => args[args.indexOf('-filter_complex') + 1];

void main() {
  test('old projects retain cover cropping and single overlay positioning', () {
    final old = VideoDocument(
      clips: [source.copyWith(cropX: .3, cropY: .7, zoom: 2)],
      overlay: const VideoOverlay(path: '/logo.png'),
    ).toJson();
    final clips = old['clips'] as List;
    for (final key in ['positionX', 'positionY', 'fit', 'filterIntensity']) {
      (clips.first as Map).remove(key);
    }
    old['overlay'] = (old.remove('overlays') as List).first;
    (old['overlay'] as Map).remove('centered');
    final document = VideoDocument.fromJson(old);
    expect(document.clips.first.fit, VideoFit.fill);
    expect(document.clips.first.positionX, 0);
    expect(document.clips.first.filterIntensity, 1);
    expect(document.overlays, hasLength(1));
    expect(document.overlay!.centered, isFalse);
    final placement = VideoCanvasPlacement.forClip(
      document.clips.first,
      canvasWidth: 320,
      canvasHeight: 180,
    );
    expect(placement.left, -96);
    expect(placement.top, closeTo(-126, .00001));
    expect(placement.width, 640);
  });

  test(
    'fit, pinch and translation use the same normalized canvas at every resolution',
    () {
      final clip = source.copyWith(
        fit: VideoFit.fit,
        zoom: .8,
        positionX: .15,
        positionY: -.1,
      );
      final preview = VideoCanvasPlacement.forClip(
        clip,
        canvasWidth: 180,
        canvasHeight: 320,
      );
      final export = VideoCanvasPlacement.forClip(
        clip,
        canvasWidth: 1080,
        canvasHeight: 1920,
      );
      expect(export.left, closeTo(preview.left * 6, .00001));
      expect(export.top, closeTo(preview.top * 6, .00001));
      expect(export.width, closeTo(preview.width * 6, .00001));
      expect(export.height, closeTo(preview.height * 6, .00001));
      expect(preview.width, closeTo(144, .001));
      expect(preview.left, closeTo(45, .001));
      expect(preview.top, closeTo(87.5, .001));
      final restored = VideoClip.fromJson(clip.toJson());
      expect(restored.toJson(), clip.toJson());
      final plan = VideoRenderPlan(
        VideoDocument(clips: [restored], canvas: VideoCanvas.portrait),
        shortEdge: 1080,
      );
      final exportGraph = graph(plan.normalize(restored, '/out.mp4'));
      expect(exportGraph, contains('pad=w=1080:h=1920'));
      expect(exportGraph, contains('scale=810:486'));
      expect(
        exportGraph,
        contains('pad=w=1080:h=1920:x=270.000000:y=525.000000:color=black'),
      );
    },
  );

  test(
    'off-canvas clips remain black with audio, rather than invalid crop dimensions',
    () {
      final clip = source.copyWith(positionX: 2, zoom: .1);
      final plan = VideoRenderPlan(
        VideoDocument(clips: [clip]),
        shortEdge: 720,
      );
      final exportGraph = graph(plan.normalize(clip, '/out.mp4'));
      expect(exportGraph, contains('color=c=black:s=1280:720'));
      expect(exportGraph, isNot(contains('crop=')));
      expect(exportGraph, contains('[0:a:0]'));
      expect(exportGraph, isNot(contains('scale=12800')));
    },
  );

  test(
    'zoom exports crop the visible source before scaling, bounding frame memory',
    () {
      final clip = source.copyWith(positionX: .2, positionY: -.1, zoom: 4);
      final plan = VideoRenderPlan(
        VideoDocument(clips: [clip]),
        shortEdge: 1080,
      );
      final exportGraph = graph(plan.normalize(clip, '/out.mp4'));
      expect(exportGraph, contains('scale=1920:1080'));
      expect(exportGraph, isNot(contains('scale=7680')));
      expect(exportGraph, contains('crop=w=480.000000:h=270.000000'));
    },
  );

  test(
    'multiple centered overlays preserve their paths, order and exact export anchors',
    () {
      final document = VideoDocument(
        clips: [source],
        overlays: const [
          VideoOverlay(
            id: 'left',
            path: '/left.png',
            x: -.1,
            y: .4,
            width: .3,
            centered: true,
            originalPath: '/original.png',
          ),
          VideoOverlay(
            id: 'right',
            path: '/right.png',
            x: .8,
            y: .6,
            width: .2,
            centered: true,
          ),
        ],
        texts: const [
          VideoText(id: 't', text: 'Centered', x: .7, y: .2, centered: true),
        ],
      );
      final restored = VideoDocument.fromJson(document.toJson());
      expect(restored.overlays.map((layer) => layer.path), [
        '/left.png',
        '/right.png',
      ]);
      expect(restored.overlay!.originalPath, '/original.png');
      final args = VideoRenderPlan(restored, shortEdge: 720).finish(
        input: '/in.mp4',
        output: '/out.mp4',
        textFiles: {'t': '/text.txt'},
        fontFiles: {'StudioSans': '/font.ttf'},
      );
      expect(args, containsAll(['/left.png', '/right.png']));
      final exportGraph = graph(args);
      expect(
        exportGraph,
        contains('overlay=x=W*-0.100000-w/2:y=H*0.400000-h/2'),
      );
      expect(exportGraph, contains('[vov0][ov1]'));
      expect(
        exportGraph,
        contains('x=w*0.700000-text_w/2:y=h*0.200000-text_h/2:fix_bounds=0'),
      );
      expect(() => restored.overlays.clear(), throwsUnsupportedError);
    },
  );

  test(
    'filter strength is neutral at zero and retained through JSON and native exports',
    () {
      final clip = source.copyWith(
        filter: VideoFilter.warm,
        filterIntensity: 0,
      );
      expect(VideoPreviewColor.matrix(clip), VideoPreviewColor.identity);
      expect(
        VideoRenderPlan.filterFor(clip.filter, clip.filterIntensity),
        'null',
      );
      expect(
        VideoRenderPlan.filterFor(VideoFilter.warm, .5),
        'colorchannelmixer=rr=1.040000:gg=1.005000:bb=0.950000',
      );
      final half = VideoClip.fromJson(
        clip.copyWith(filterIntensity: .5).toJson(),
      );
      expect(VideoPreviewColor.matrix(half)[0], closeTo(1.04, .00001));
      expect(
        VideoRenderPlan.filterFor(half.filter, half.filterIntensity),
        contains('rr=1.040000'),
      );
      for (final filter in VideoFilter.values) {
        expect(VideoRenderPlan.filterFor(filter, 0), 'null');
        expect(
          VideoRenderPlan.filterFor(filter, 1),
          VideoRenderPlan.filterFor(filter),
        );
      }
    },
  );

  test(
    'processed clips retain a bounded original recipe for exact source restoration',
    () {
      final original = source.copyWith(
        start: 2,
        end: 8,
        positionX: .2,
        fit: VideoFit.fit,
      );
      final transformed = original.copyWith(
        path: '/cutout.mp4',
        start: 0,
        end: 6,
        sourceDuration: 6,
        width: 1280,
        height: 720,
        cutoutOriginal: original,
      );
      final restored = VideoClip.fromJson(transformed.toJson());
      expect(restored.cutoutOriginal!.path, '/a.mp4');
      expect(restored.cutoutOriginal!.start, 2);
      expect(restored.positionX, .2);
      expect(restored.width, 1280);
      final nested = transformed.toJson();
      (nested['cutoutOriginal'] as Map)['cutoutOriginal'] = original.toJson();
      expect(VideoClip.fromJson(nested).cutoutOriginal!.cutoutOriginal, isNull);
    },
  );
  test(
    'cutout recipes are deep immutable, bounded and cleared on restoration',
    () {
      final point = <String, dynamic>{'x': .2, 'y': .4};
      final recipe = <String, dynamic>{
        'automatic': true,
        'backgroundColor': 0xff123456,
        'backgroundPath': '/background.png',
        'strokes': [
          {
            'mode': 'erase',
            'radius': .05,
            'points': [point],
          },
        ],
      };
      final clip = source.copyWith(
        cutoutRecipe: recipe,
        cutoutOriginal: source,
      );
      point['x'] = .9;
      final strokes = clip.cutoutRecipe!['strokes'] as List;
      expect((strokes.single['points'] as List).single['x'], .2);
      expect(() => strokes.clear(), throwsUnsupportedError);
      expect(VideoClip.fromJson(clip.toJson()).cutoutRecipe, clip.cutoutRecipe);
      expect(clip.copyWith(clearCutoutOriginal: true).cutoutRecipe, isNull);
      expect(
        () => source.copyWith(
          cutoutRecipe: {'strokes': List.filled(201, recipe['strokes'][0])},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'large off-canvas image overlays crop before scaling and invisible layers use no decoder',
    () {
      final document = VideoDocument(
        clips: [source],
        overlays: const [
          VideoOverlay(
            id: 'large',
            path: '/tall.png',
            centered: true,
            x: .5,
            y: .5,
            width: 2,
          ),
          VideoOverlay(
            id: 'hidden',
            path: '/hidden.png',
            centered: true,
            x: 1.5,
            y: 1.5,
            width: .1,
          ),
        ],
      );
      final args = VideoRenderPlan(document, shortEdge: 720).finish(
        input: '/in.mp4',
        output: '/out.mp4',
        textFiles: {},
        fontFiles: {},
        overlaySizes: {'/tall.png': (400, 4000), '/hidden.png': (400, 400)},
      );
      final exportGraph = graph(args);
      expect(exportGraph, contains('format=rgba,crop='));
      expect(exportGraph, contains('scale=1280:720'));
      expect(exportGraph, isNot(contains('scale=2560:25600')));
      expect(args, isNot(contains('/hidden.png')));
      expect(document.overlays, hasLength(2));
    },
  );
}
