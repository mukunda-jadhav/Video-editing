import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../domain/ad_gateway.dart';
import 'ads_providers.dart';

class WorkspaceAdSlot extends ConsumerWidget {
  const WorkspaceAdSlot({super.key, required this.placement});
  final AdPlacement placement;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(entitlementProvider);
    final coordinator = ref.watch(adsCoordinatorProvider);
    final creative = ref.watch(workspaceAdProvider(placement)).asData?.value;
    if (creative == null || !coordinator.canShow(placement)) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: 'Advertisement',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Advertisement',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Text(
                creative.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(creative.body),
            ],
          ),
        ),
      ),
    );
  }
}

class AdsPreferencesSection extends ConsumerStatefulWidget {
  const AdsPreferencesSection({super.key});
  @override
  ConsumerState<AdsPreferencesSection> createState() =>
      _AdsPreferencesSectionState();
}

class _AdsPreferencesSectionState extends ConsumerState<AdsPreferencesSection> {
  bool _saving = false;
  String? _error;
  Future<void> _change(bool enabled) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adConsentRepositoryProvider)
          .setConsent(enabled ? AdConsent.contextual : AdConsent.denied);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save the preference. Ads remain hidden.',
        );
      }
    } finally {
      if (mounted) {
        ref.invalidate(adConsentProvider);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(adConsentProvider);
    final configured = ref.watch(adGatewayProvider).isConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ads and privacy', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          configured
              ? 'Optional contextual ads can appear on Home and Projects for Free users. '
                    'Pro has no ads. Ads never interrupt editing or export.'
              : 'No ad network is connected in this build. No advertising requests, '
                    'tracking or personalized ads are made.',
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow contextual workspace ads'),
          subtitle: const Text(
            'Optional. Your media is never used for advertising.',
          ),
          value: consent.asData?.value == AdConsent.contextual,
          onChanged: _saving || consent.isLoading ? null : _change,
        ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
      ],
    );
  }
}
