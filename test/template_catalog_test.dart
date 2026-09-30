import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/photo_editor/domain/photo_document.dart';
import 'package:framelab/features/templates/domain/template_catalog.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';

void main() {
  test('catalog covers every requested format without an access tier', () {
    expect(templateCatalog.map((template) => template.category).toSet(), {
      'Instagram posts',
      'Stories',
      'Reels',
      'YouTube thumbnails',
      'Product ads',
      'Festival posters',
      'Business posters',
    });
    expect(templateCatalog.length, 14);
    expect(templateCatalog.any((template) => template.video), isTrue);
    expect(templateCatalog.map((template) => template.headlineFont).toSet(), {
      'StudioSans',
      'StudioDisplay',
    });
    expect(
      templateCatalog.map((template) => template.id).toSet().length,
      templateCatalog.length,
    );
  });

  for (final template in templateCatalog) {
    test('${template.id} creates an editable, roundtrippable recipe', () {
      final recipe = template.createRecipe();
      if (template.video) {
        final document = VideoDocument.fromJson(recipe);
        expect(document.title, template.title);
        expect(document.canvas, VideoCanvas.portrait);
        expect(document.clips, isEmpty);
        expect(document.texts, isNotEmpty);
        expect(
          document.texts.first.text,
          template.headline.replaceAll('\n', ' '),
        );
        expect(
          VideoDocument.fromJson(document.toJson()).toJson(),
          document.toJson(),
        );
      } else {
        final document = PhotoDocument.fromJson(recipe);
        expect(document.title, template.title);
        expect(
          (document.width, document.height),
          (template.width, template.height),
        );
        expect(document.backgroundColor, template.background);
        expect(
          document.layers.where((layer) => layer.kind == 'text'),
          isNotEmpty,
        );
        expect(
          document.layers.any((layer) => layer.text == template.headline),
          isTrue,
        );
        expect(document.layers.any((layer) => layer.kind != 'text'), isTrue);
        expect(
          PhotoDocument.fromJson(document.toJson()).toJson(),
          document.toJson(),
        );
      }
    });

    test('${template.id} gives each project an independent copy', () {
      final first = template.createRecipe();
      final second = template.createRecipe();
      final untouched = template.createRecipe();
      first['title'] = 'My custom design';
      final layerKey = template.video ? 'texts' : 'layers';
      final layers = first[layerKey] as List<dynamic>;
      (layers.first as Map<String, dynamic>)['color'] = 0;
      layers.clear();
      expect(second, untouched);
      expect(template.createRecipe(), untouched);
    });
  }
}
