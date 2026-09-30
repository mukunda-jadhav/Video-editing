import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app/app.dart';
import 'app/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/config/bundled_licenses.dart';
import 'features/projects/data/local_project_repository.dart';
import 'features/entitlements/data/local_mock_entitlement_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 80;
  try {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'projects'));
    await root.create(recursive: true);
    final entitlement = LocalMockEntitlementRepository();
    await entitlement.initialize();
    runApp(
      ProviderScope(
        overrides: [
          projectRepositoryProvider.overrideWithValue(
            LocalProjectRepository(root),
          ),
          entitlementRepositoryProvider.overrideWithValue(entitlement),
        ],
        child: const FrameLabApp(),
      ),
    );
  } on Object {
    runApp(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_off_outlined, size: 48),
                    const SizedBox(height: 24),
                    const Text(
                      'FrameLab could not open local storage. Free some device storage, then retry.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: main, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
