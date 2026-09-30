import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../features/projects/domain/project_document.dart';
import 'native_media_service.dart';

class MediaImportService {
  MediaImportService(this.projects, this.native);
  final ProjectStore projects;
  final NativeMediaService native;
  final _random = Random.secure();

  Future<List<String>> pick(
    String projectId,
    FileType type, {
    bool multiple = false,
  }) async {
    final List<PlatformFile> selection;
    if (multiple) {
      selection = await FilePicker.pickFiles(type: type);
    } else {
      final file = await FilePicker.pickFile(type: type);
      selection = file == null ? [] : [file];
    }
    if (selection.isEmpty) return [];
    final directory = await projects.assetsDirectory(projectId);
    final copied = <String>[];
    try {
      for (final picked in selection) {
        final source = picked.path;
        if (source == null) {
          throw const FileSystemException(
            'The selected media could not be opened. Choose a local file.',
          );
        }
        final file = File(source);
        final size = await file.length();
        if (size <= 0) {
          throw const FileSystemException('The selected file is empty.');
        }
        final free = await native.availableBytes();
        if (free < size + 64 * 1024 * 1024) {
          throw const FileSystemException(
            'Not enough storage to import this media.',
          );
        }
        var extension = p.extension(source).toLowerCase();
        if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
          extension = '.media';
        }
        final name =
            '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 30)}$extension';
        final target = p.join(directory, name);
        copied.add(target);
        await file.copy(target);
      }
      return copied;
    } on Object {
      for (final file in copied) {
        try {
          await File(file).delete();
        } on FileSystemException {
          /* Keep original import failure. */
        }
      }
      rethrow;
    }
  }
}
