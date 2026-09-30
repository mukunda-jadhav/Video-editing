import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_render_plan.dart';

const source = VideoClip(
  id: 'a',
  path: '/private/input with spaces.mp4',
  sourceDuration: 10,
  end: 10,
);
String graph(List<String> args) => args[args.indexOf('-filter_complex') + 1];

void main() {
  test('720p landscape and 1080p portrait use even export dimensions', () {
    final wide = VideoRenderPlan(
      VideoDocument(clips: [source]),
      shortEdge: 720,
    );
    final tall = VideoRenderPlan(
      VideoDocument(clips: [source], canvas: VideoCanvas.portrait),
      shortEdge: 1080,
    );
    expect([wide.width, wide.height], [1280, 720]);
    expect([tall.width, tall.height], [1080, 1920]);
  });

  test('future 4K and invalid recipes cannot reach FFmpeg', () {
    expect(
      () => VideoRenderPlan(VideoDocument(clips: [source]), shortEdge: 2160),
      throwsArgumentError,
    );
    expect(
      () => VideoRenderPlan(VideoDocument(), shortEdge: 720),
      throwsArgumentError,
    );
    expect(
      () => VideoRenderPlan(
        VideoDocument(clips: [source.copyWith(speed: 0)]),
        shortEdge: 720,
      ),
      throwsArgumentError,
    );
    expect(
      () => VideoRenderPlan(
        VideoDocument(clips: [source.copyWith(end: 11)]),
        shortEdge: 720,
      ),
      throwsArgumentError,
    );
  });

  test(
    'source path remains an argument and trim speed crop audio compile together',
    () {
      final edited = source.copyWith(
        start: 2,
        end: 8,
        speed: .25,
        volume: 0,
        cropX: .3,
        cropY: .7,
        zoom: 2,
        filter: VideoFilter.warm,
        effect: VideoEffect.mirror,
      );
      final args = VideoRenderPlan(
        VideoDocument(clips: [edited]),
        shortEdge: 720,
      ).normalize(edited, '/out/video.mp4');
      expect(args[args.indexOf('-i') + 1], source.path);
      expect(args[args.indexOf('-ss') + 1], '2.000000');
      expect(args[args.indexOf('-t') + 1], '6.000000');
      expect(graph(args), contains('setpts=(PTS-STARTPTS)/0.250000'));
      expect(graph(args), contains('atempo=0.5,atempo=0.500000'));
      expect(graph(args), contains('volume=0.000000'));
      expect(graph(args), contains('hflip'));
      expect(graph(args), contains('scale=1280:720'));
    },
  );

  test('silent clips get a bounded synthetic audio track', () {
    const silent = VideoClip(
      id: 's',
      path: '/silent.mp4',
      sourceDuration: 3,
      end: 3,
      hasAudio: false,
    );
    final args = VideoRenderPlan(
      VideoDocument(clips: [silent]),
      shortEdge: 480,
    ).normalize(silent, '/normalized.mp4');
    expect(
      graph(args),
      contains('anullsrc=r=48000:cl=stereo,atrim=duration=3.000000'),
    );
    expect(graph(args), isNot(contains('[0:a:0]')));
  });

  test('all transition recipes use normalized frame and audio composition', () {
    for (final transition in VideoTransition.values) {
      final document = VideoDocument(
        clips: [
          source.copyWith(transition: transition),
          source.copyWith(id: 'b'),
        ],
      );
      final args = VideoRenderPlan(document, shortEdge: 720).stitch(
        left: '/a.mp4',
        right: '/b.mp4',
        output: '/out.mp4',
        leftDuration: 10,
        boundary: 0,
      );
      if (transition == VideoTransition.cut) {
        expect(graph(args), contains('concat=n=2:v=1:a=1'));
      } else {
        expect(graph(args), contains('xfade=transition='));
        expect(graph(args), contains('offset=9.500000'));
        expect(graph(args), contains('acrossfade=d=0.500000'));
      }
    }
  });

  test(
    'caption text never enters filter graph and music overlay timing is compiled',
    () {
      final document = VideoDocument(
        clips: [source],
        texts: const [
          VideoText(
            id: 't',
            text: "100% 'quoted' : ; [evil]",
            start: 1,
            end: 4,
          ),
        ],
        musicPath: '/music with spaces.mp3',
        musicVolume: .5,
        overlay: const VideoOverlay(
          path: '/logo.png',
          start: 2,
          end: 5,
          opacity: .6,
        ),
      );
      final args = VideoRenderPlan(document, shortEdge: 720).finish(
        input: '/sequence.mp4',
        output: '/out.mp4',
        textFiles: {'t': '/job/text.txt'},
        fontFiles: {'StudioSans': '/job/font.ttf'},
        preparedMusic: '/job/music.wav',
      );
      expect(graph(args), isNot(contains('evil')));
      expect(graph(args), contains('expansion=none'));
      expect(graph(args), contains('textfile='));
      expect(graph(args), contains('between(t,1.000000,4.000000)'));
      expect(graph(args), contains('between(t,2.000000,5.000000)'));
      expect(graph(args), contains('amix=inputs=2:duration=first'));
      expect(args, contains('/job/music.wav'));
      expect(args, isNot(contains('/music with spaces.mp3')));
      // Final composition only consumes the prepared finite audio track.
      expect(args.where((argument) => argument == '-t'), hasLength(2));
      expect(args, isNot(contains('-stream_loop')));
      expect(args, contains('h264_mediacodec'));
      expect(
        () => VideoRenderPlan(
          document,
          shortEdge: 720,
        ).finish(input: '/s', output: '/o', textFiles: {}, fontFiles: {}),
        throwsArgumentError,
      );
    },
  );

  test('music is bounded and resampled before final composition', () {
    final plan = VideoRenderPlan(
      VideoDocument(clips: [source], musicPath: '/song.mp3', musicVolume: .4),
      shortEdge: 720,
    );
    final args = plan.prepareMusic(output: '/music.wav', repeats: 3, offset: 2);
    expect(args[args.indexOf('-stream_loop') + 1], '3');
    expect(args[args.indexOf('-ss') + 1], '2.000000');
    expect(args[args.indexOf('-t') + 1], '10.000000');
    expect(args[args.indexOf('-af') + 1], contains('aresample=48000'));
    expect(args, contains('pcm_f32le'));
    expect(
      graph(
        plan.finish(
          input: '/sequence.mp4',
          output: '/out.mp4',
          textFiles: {},
          fontFiles: {},
          preparedMusic: '/music.wav',
        ),
      ),
      contains('volume=0.400000'),
    );
    expect(
      () => plan.finish(
        input: '/sequence.mp4',
        output: '/out.mp4',
        textFiles: {},
        fontFiles: {},
      ),
      throwsArgumentError,
    );
  });

  test('every filter and basic effect compiles without external assets', () {
    for (final filter in VideoFilter.values) {
      for (final effect in VideoEffect.values) {
        final clip = source.copyWith(filter: filter, effect: effect);
        final plan = VideoRenderPlan(
          VideoDocument(clips: [clip]),
          shortEdge: 480,
        );
        expect(
          graph(plan.normalize(clip, '/o.mp4')),
          contains('format=yuv420p'),
        );
      }
    }
  });
}
