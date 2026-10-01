import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/photo_editor/domain/photo_document.dart';

void main() {
  test('old projects keep centered image and full filter strength', () {
    final document = PhotoDocument.fromJson({'imagePath': '/source.png'});
    expect(
      (
        document.imageX,
        document.imageY,
        document.imageScale,
        document.imageRotation,
      ),
      (0, 0, 1, 0),
    );
    expect(document.filterIntensity, 1);
    document.imageX = .2;
    document.imageY = -.1;
    document.imageScale = .7;
    document.imageRotation = math.pi / 7;
    document.filterIntensity = .4;
    document.originalImagePath = '/original.png';
    document.layers.add(
      PhotoLayer(
        id: 'overlay',
        kind: 'image',
        path: '/cutout.png',
        originalPath: '/overlay.png',
      ),
    );
    expect(
      PhotoDocument.fromJson(document.toJson()).toJson(),
      document.toJson(),
    );
  });
  test('newer photo schemas are rejected before autosave can change them', () {
    expect(
      () => PhotoDocument.fromJson({'version': 99}),
      throwsFormatException,
    );
  });
  test(
    'oversized layer lists are rejected without discarding saved layers',
    () {
      final layers = List.generate(
        PhotoDocument.maxLayers,
        (index) => PhotoLayer(id: '$index').toJson(),
      );
      expect(
        PhotoDocument.fromJson({'layers': layers}).layers.length,
        PhotoDocument.maxLayers,
      );
      layers.add(PhotoLayer(id: 'extra').toJson());
      expect(
        () => PhotoDocument.fromJson({'layers': layers}),
        throwsFormatException,
      );
      expect(layers.length, PhotoDocument.maxLayers + 1);
    },
  );
  test(
    'all edits and template layer attributes survive saving and reopening',
    () {
      final document = PhotoDocument(
        title: 'Summer poster',
        imagePath: '/private/source.png',
        backgroundPath: '/private/background.jpg',
        width: 1080,
        height: 1920,
        imageFit: 'contain',
        rotation: 3,
        flipHorizontal: true,
        cropLeft: .15,
        cropTop: .1,
        cropRight: .85,
        cropBottom: .9,
        brightness: 1.3,
        contrast: .8,
        saturation: 1.5,
        exposure: -.5,
        blur: 8,
        filter: 'Sepia',
        backgroundColor: 0x884422ff,
        layers: [
          PhotoLayer(
            id: 'headline',
            text: 'Stay curious',
            fontFamily: 'StudioSerif',
            fontSize: .12,
            bold: false,
            x: .2,
            y: .3,
            width: .6,
            height: .3,
            rotation: math.pi / 8,
            opacity: .7,
          ),
          PhotoLayer(
            id: 'product',
            kind: 'image',
            path: '/private/product.png',
          ),
        ],
      );
      expect(
        PhotoDocument.fromJson(document.toJson()).toJson(),
        document.toJson(),
      );
    },
  );

  test('corrupt crop ranges and nonfinite values normalize safely', () {
    final doc = PhotoDocument.fromJson({
      'width': -20,
      'height': 999999,
      'cropLeft': .9,
      'cropRight': .1,
      'cropTop': .95,
      'cropBottom': -.4,
      'brightness': double.nan,
      'blur': double.infinity,
      'rotation': -1,
      'layers': [
        false,
        null,
        <String, Object?>{'id': 'valid', 'opacity': 5},
      ],
    });
    expect((doc.width, doc.height), (64, 4096));
    expect(doc.cropRight - doc.cropLeft, closeTo(.05, .0001));
    expect(doc.cropBottom - doc.cropTop, closeTo(.05, .0001));
    expect(doc.brightness, 1);
    expect(doc.blur, 0);
    expect(doc.rotation, 3);
    expect(doc.layers.single.opacity, 1);
  });

  test('export limits preserve aspect ratio without upscaling', () {
    final doc = PhotoDocument(width: 4000, height: 3000);
    expect(doc.exportSize(), (4000, 3000));
    expect(doc.exportSize(), (4000, 3000));
    final small = PhotoDocument(width: 320, height: 200);
    expect(small.exportSize(), (320, 200));
  });

  test('undo is independent from mutations and editing discards redo', () {
    final doc = PhotoDocument(
      layers: [PhotoLayer(id: '1', text: 'Before')],
    );
    final history = PhotoHistory(doc);
    doc.layers.first.text = 'After';
    history.commit(doc);
    final undone = history.undo();
    expect(undone.layers.first.text, 'Before');
    undone.layers.first.text = 'New branch';
    history.commit(undone);
    expect(history.canRedo, isFalse);
    expect(history.undo().layers.first.text, 'Before');
  });

  test('history keeps at most forty recipes', () {
    final doc = PhotoDocument();
    final history = PhotoHistory(doc);
    for (var index = 0; index < 100; index++) {
      doc.title = '$index';
      history.commit(doc);
    }
    var undoCount = 0;
    while (history.canUndo) {
      history.undo();
      undoCount++;
    }
    expect(undoCount, 39);
  });

  test(
    'saved filters fonts and stickers remain editable without access flags',
    () {
      final document = PhotoDocument(
        filter: 'Vivid',
        layers: [
          PhotoLayer(id: 'text', kind: 'text', fontFamily: 'StudioScript'),
          PhotoLayer(id: 'sticker', kind: 'heart'),
        ],
      );
      final restored = PhotoDocument.fromJson(document.toJson());
      expect(restored.filter, 'Vivid');
      expect(restored.layers.first.fontFamily, 'StudioScript');
      expect(restored.layers.last.kind, 'heart');
      expect(restored.toJson().keys, isNot(contains('premium')));
    },
  );
}
