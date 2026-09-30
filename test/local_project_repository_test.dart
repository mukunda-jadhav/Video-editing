import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/projects/data/local_project_repository.dart';
import 'package:framelab/features/projects/domain/project_document.dart';
import 'package:framelab/features/projects/domain/project_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LocalProjectRepository repository;

  ProjectDocument document(
    String id, {
    String title = 'My edit',
    DateTime? updatedAt,
    Map<String, dynamic>? recipe,
  }) => ProjectDocument(
    id: id,
    kind: ProjectKind.photo,
    title: title,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
    recipe: recipe ?? <String, dynamic>{'width': 1080, 'layers': <dynamic>[]},
    thumbnailPath: '$id/assets/thumbnail.png',
  );

  File manifest(String id, [String name = 'project.json']) =>
      File(p.join(root.path, id, name));

  Future<void> writeManifest(
    String id,
    Map<String, dynamic> data, {
    String name = 'project.json',
  }) async {
    final file = manifest(id, name);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('framelab_project_test_');
    repository = LocalProjectRepository(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('empty store is usable and nonexistent projects return null', () async {
    expect(await repository.load('missing'), isNull);
    expect(await repository.listRecent(), isEmpty);
    expect(repository.damagedProjectIds, isEmpty);
  });

  test('save survives restart with metadata and full recipe intact', () async {
    final original = document(
      'one',
      recipe: {
        'width': 1920,
        'source': 'one/assets/original.jpg',
        'layers': [
          {'id': 'text', 'text': 'A local story', 'color': 0xffaabbcc},
        ],
      },
    );
    await repository.save(original);
    final restarted = LocalProjectRepository(root);
    expect((await restarted.load('one'))!.toJson(), original.toJson());
    expect(await manifest('one', 'project.pending').exists(), isFalse);
    expect((await restarted.listRecent()).single.title, original.title);
  });

  test('save snapshots the recipe before queued work can mutate it', () async {
    final original = document(
      'one',
      recipe: {
        'layers': [
          {'text': 'At save time'},
        ],
      },
    );
    final saving = repository.save(original);
    (original.recipe['layers'] as List<dynamic>).clear();
    await saving;
    final loaded = await repository.load('one');
    expect(loaded!.recipe['layers'], [
      {'text': 'At save time'},
    ]);
  });

  test(
    'writes and reads preserve submission order across rapid edits',
    () async {
      final operations = <Future<void>>[];
      for (var index = 0; index < 15; index++) {
        operations.add(repository.save(document('one', title: 'Edit $index')));
      }
      final readBeforeLastSave = repository.load('one');
      operations.add(repository.save(document('one', title: 'Final edit')));
      await Future.wait(operations);
      expect((await readBeforeLastSave)!.title, 'Edit 14');
      expect(
        (await LocalProjectRepository(root).load('one'))!.title,
        'Final edit',
      );
    },
  );

  test(
    'corrupt current recovers backup and a later save keeps it valid',
    () async {
      final previous = document('one', title: 'Recoverable edit');
      await repository.save(previous);
      await repository.save(document('one', title: 'Later edit'));
      await manifest('one').writeAsString('{interrupted');
      expect((await repository.load('one'))!.toJson(), previous.toJson());

      await repository.save(document('one', title: 'Recovered and edited'));
      expect((await repository.load('one'))!.title, 'Recovered and edited');
      await manifest('one').writeAsString('{broken again');
      expect((await repository.load('one'))!.toJson(), previous.toJson());
    },
  );

  test(
    'first save interrupted before rename recovers the pending recipe',
    () async {
      final pending = document('new', title: 'First save');
      await writeManifest('new', pending.toJson(), name: 'project.pending');
      expect((await repository.load('new'))!.toJson(), pending.toJson());
      expect((await repository.listRecent()).single.id, 'new');
      await repository.save(document('new', title: 'Resumed editing'));
      expect((await repository.load('new'))!.title, 'Resumed editing');
      await manifest('new').writeAsString('damaged');
      expect((await repository.load('new'))!.toJson(), pending.toJson());
    },
  );

  test(
    'interrupted replacement prefers committed backup over pending',
    () async {
      await writeManifest(
        'one',
        document('one', title: 'Committed').toJson(),
        name: 'project.bak',
      );
      await writeManifest(
        'one',
        document('one', title: 'Not yet committed').toJson(),
        name: 'project.pending',
      );
      expect((await repository.load('one'))!.title, 'Committed');
    },
  );

  test('deleting a project preserves other projects and their media', () async {
    await repository.save(document('one'));
    await repository.save(document('two', updatedAt: DateTime.utc(2026, 2, 1)));
    final assets = await repository.assetsDirectory('two');
    final retainedMedia = File(p.join(assets, 'source.jpg'));
    await retainedMedia.writeAsBytes([1, 2, 3]);
    expect((await repository.listRecent()).map((p) => p.id), ['two', 'one']);
    await repository.delete('one');
    await repository.delete('missing');
    final restarted = LocalProjectRepository(root);
    expect(await restarted.load('one'), isNull);
    expect((await restarted.listRecent()).single.id, 'two');
    expect(await retainedMedia.readAsBytes(), [1, 2, 3]);
  });

  test(
    'invalid and traversal IDs cannot read write or delete outside root',
    () async {
      final safe = document('safe');
      await repository.save(safe);
      for (final id in [
        '',
        '..',
        '../safe',
        r'..\safe',
        '/safe',
        r'C:\safe',
        'has space',
        'a' * 81,
      ]) {
        await expectLater(repository.load(id), throwsArgumentError);
        await expectLater(repository.assetsDirectory(id), throwsArgumentError);
        await expectLater(repository.save(document(id)), throwsArgumentError);
        await expectLater(repository.delete(id), throwsArgumentError);
      }
      expect((await repository.load('safe'))!.toJson(), safe.toJson());
    },
  );

  test(
    'damaged projects are reported while valid projects remain listed',
    () async {
      await repository.save(document('good'));
      await writeManifest('wrong-id', document('different-id').toJson());
      await writeManifest(
        'future',
        document('future').toJson()..['schemaVersion'] = 99,
      );
      await manifest('broken').parent.create(recursive: true);
      await manifest('broken').writeAsString('not json');
      await Directory(p.join(root.path, 'orphan')).create();
      expect((await repository.listRecent()).map((p) => p.id), ['good']);
      expect(
        repository.damagedProjectIds,
        unorderedEquals(['wrong-id', 'future', 'broken']),
      );
      await expectLater(repository.load('future'), throwsFormatException);
      await repository.delete('wrong-id');
      await repository.delete('future');
      await repository.delete('broken');
      await repository.listRecent();
      expect(repository.damagedProjectIds, isEmpty);
    },
  );

  test(
    'unknown schema is rejected without rewriting the saved manifest',
    () async {
      final future = document('future').toJson()..['schemaVersion'] = 999;
      await writeManifest('future', future);
      final bytes = await manifest('future').readAsBytes();
      await expectLater(repository.load('future'), throwsFormatException);
      expect(await manifest('future').readAsBytes(), bytes);
      expect(() => ProjectDocument.fromJson(future), throwsFormatException);
    },
  );

  test(
    'metadata limit measures UTF-8 bytes and a failed save leaves old data',
    () async {
      final previous = document('one');
      await repository.save(previous);
      final tooLarge = document(
        'one',
        recipe: {'text': 'अ' * (3 * 1024 * 1024)},
      );
      await expectLater(
        repository.save(tooLarge),
        throwsA(isA<FileSystemException>()),
      );
      expect((await repository.load('one'))!.toJson(), previous.toJson());
      await repository.save(document('one', title: 'Queue still works'));
      expect((await repository.load('one'))!.title, 'Queue still works');
    },
  );
}
