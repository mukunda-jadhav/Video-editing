import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/widgets/page_content.dart';
import '../../ads/presentation/ads_widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Your studio settings')),
    body: PageContent(
      children: [
        const InfoPanel(
          title: 'Your media stays with you',
          body:
              'Photos, videos, edit recipes and background removal stay on this device. FrameLab does not upload your media. No account is needed for free editing.',
          icon: Icons.lock_outline_rounded,
        ),
        const SizedBox(height: 16),
        const InfoPanel(
          title: 'Local projects and exports',
          body:
              'Projects autosave in app-private storage. Uninstalling the app removes local projects. Export finished images to Pictures/FrameLab and videos to Movies/FrameLab to keep them in your gallery.',
          icon: Icons.folder_outlined,
        ),
        const SizedBox(height: 16),
        const AdsPreferencesSection(),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Premium and local test purchases'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/upgrade'),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licenses'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'FrameLab',
            applicationVersion: '1.0.0',
            applicationLegalese:
                'Original interface and templates. On-device U²-Net-P model, ONNX Runtime and LGPL FFmpeg. No paid AI APIs.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: const Text('Local device diagnostics'),
          subtitle: const Text('Shown on this device; never sent anywhere'),
          onTap: () async {
            try {
              final info = await ref
                  .read(nativeMediaServiceProvider)
                  .diagnostics();
              if (context.mounted) {
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Device diagnostics'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        info.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join('\n'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }
            } on Object {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Diagnostics are available on Android.'),
                  ),
                );
              }
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: const Text('Build roadmap'),
          subtitle: const Text(
            'See the editing, privacy and store-readiness plan',
          ),
          onTap: () => context.push('/roadmap'),
        ),
        const SizedBox(height: 24),
        const Text(
          'Export quality: Free photos up to 1920px; Pro up to 4096px. Video: 720p Free, 1080p Pro. 4K video and additional premium on-device tools are future capabilities. Codec support depends on the device.',
        ),
      ],
    ),
  );
}
