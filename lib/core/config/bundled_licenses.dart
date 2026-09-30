import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Make notices for bundled fonts and native/model dependencies available
/// offline in Settings, alongside Flutter's automatically collected licenses.
bool _registered = false;

void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Sans', 'Serif', 'Mono', 'Script', 'Display']) {
      yield LicenseEntryWithLineBreaks([
        'Studio$font font',
      ], await rootBundle.loadString('assets/fonts/Studio$font-OFL.txt'));
    }
    for (final entry in const {
      'U²-Net-P model': 'U2NET-LICENSE.txt',
      'rembg ONNX conversion': 'REMBG-LICENSE.txt',
      'ONNX Runtime': 'ONNX-RUNTIME-LICENSE.txt',
      'FFmpegKit Full': 'FFMPEG-KIT-LICENSE.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/licenses/${entry.value}'));
    }
  });
}
