import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_history.dart';

VideoClip clip(String id, {double seconds = 10}) => VideoClip(
  id: id,
  path: '/private/$id.mp4',
  sourceDuration: seconds,
  end: seconds,
);

void main() {
  test('project roundtrip preserves all editing decisions', () {
    final document = VideoDocument(
      title: 'Private trip',
      canvas: VideoCanvas.portrait,
      clips: [
        clip('a').copyWith(
          start: 1,
          end: 8,
          speed: .5,
          volume: 0,
          cropX: .2,
          cropY: .6,
          zoom: 1.7,
          filter: VideoFilter.cinema,
          effect: VideoEffect.fade,
          transition: VideoTransition.wipe,
          transitionDuration: 1,
        ),
        clip('b'),
      ],
      texts: const [
        VideoText(
          id: 't',
          text: 'A quote: \'hello\'\n100%',
          font: 'StudioMono',
          start: 2,
          end: 6,
          x: .3,
          y: .4,
          color: 0xffffcf5c,
          background: false,
        ),
      ],
      overlay: const VideoOverlay(
        path: '/private/logo.png',
        opacity: .7,
        start: 1,
        end: 9,
      ),
      musicPath: '/private/song.mp3',
      musicStart: 12,
      musicVolume: .8,
    );
    expect(
      VideoDocument.fromJson(document.toJson()).toJson(),
      document.toJson(),
    );
  });

  test('transition overlap respects neighboring clip duration', () {
    final document = VideoDocument(
      clips: [
        clip(
          'a',
          seconds: 1,
        ).copyWith(transition: VideoTransition.dissolve, transitionDuration: 2),
        clip('b', seconds: .2),
      ],
    );
    expect(document.transitionAt(0), closeTo(.1, .0001));
    expect(document.duration, closeTo(1.1, .0001));
    expect(document.transitionAt(-1), 0);
    expect(document.transitionAt(1), 0);
  });

  test('split preserves source, speed, duration and outgoing transition', () {
    final original = clip(
      'a',
    ).copyWith(start: 1, end: 9, speed: 2, transition: VideoTransition.circle);
    final result = splitVideoClip(original, 5, 'new');
    expect(result.map((c) => c.path).toSet(), {original.path});
    expect(result.first.duration + result.last.duration, original.duration);
    expect(result.first.transition, VideoTransition.cut);
    expect(result.last.transition, VideoTransition.circle);
    expect(result.last.id, 'new');
    expect(() => splitVideoClip(original, 1, 'bad'), throwsArgumentError);
    expect(
      () => splitVideoClip(original, double.nan, 'bad'),
      throwsArgumentError,
    );
  });

  test('history branches correctly and retains bounded recipes', () {
    final initial = VideoDocument(clips: [clip('a')]);
    final history = VideoHistory(initial, limit: 3);
    history.commit(initial.copyWith(title: 'two'));
    history.commit(initial.copyWith(title: 'three'));
    history.commit(initial.copyWith(title: 'four'));
    expect(history.undo().title, 'three');
    expect(history.undo().title, 'two');
    expect(history.canUndo, false);
    expect(history.redo().title, 'three');
    history.commit(initial.copyWith(title: 'branch'));
    expect(history.canRedo, false);
    history.commit(initial.copyWith(title: 'branch'));
    expect(history.undo().title, 'three');
  });

  test('saved numeric values are bounded and unknown enums are safe', () {
    final json = clip('a').toJson()
      ..['speed'] = 100
      ..['volume'] = -5
      ..['zoom'] = double.nan
      ..['filter'] = 'unrecognized';
    final parsed = VideoClip.fromJson(json);
    expect(parsed.speed, 4);
    expect(parsed.volume, 0);
    expect(parsed.zoom, 1);
    expect(parsed.filter, VideoFilter.original);
    expect(
      () => VideoDocument.fromJson({'schemaVersion': 99, 'type': 'video'}),
      throwsFormatException,
    );
  });

  test('document cannot mutate its recipe collections from outside', () {
    final source = [clip('a')];
    final document = VideoDocument(clips: source);
    source.clear();
    expect(document.clips, hasLength(1));
    expect(() => document.clips.clear(), throwsUnsupportedError);
  });
}
