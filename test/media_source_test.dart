import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/media/media_engine.dart';

void main() {
  group('local-only media source', () {
    for (final address in [
      'https://example.com/private-photo.jpg',
      'http://example.com/video.mp4',
      'ftp://example.com/video.mp4',
      'data:image/png;base64,AAAA',
      'photo.jpg',
      'file://remote-server/share/video.mp4',
      'content:/missing-authority',
      'content://media',
    ]) {
      test('rejects $address', () {
        expect(
          () => MediaSource(uri: Uri.parse(address), kind: MediaKind.photo),
          throwsArgumentError,
        );
      });
    }

    for (final address in [
      'file:///storage/emulated/0/DCIM/photo.jpg',
      'content://media/external/video/media/42',
    ]) {
      test('accepts local platform URI $address', () {
        final uri = Uri.parse(address);
        final source = MediaSource(uri: uri, kind: MediaKind.video);
        expect(source.uri, uri);
        expect(source.kind, MediaKind.video);
      });
    }
  });
}
