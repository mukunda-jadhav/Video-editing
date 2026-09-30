import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../core/widgets/page_content.dart';
import '../domain/development_phase.dart';

class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('The build roadmap')),
    body: PageContent(
      children: [
        Text(
          'Small steps. Big possibilities.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Photo, video, templates and local projects are available. Store setup and broader Android device testing remain before public release.',
        ),
        const SizedBox(height: 24),
        for (final phase in developmentPhases)
          Card(
            child: ExpansionTile(
              key: ValueKey('phase-${phase.number}'),
              leading: CircleAvatar(child: Text('${phase.number}')),
              title: Text(phase.title),
              subtitle: Text(
                phase.number == 10
                    ? 'Optimizations included · device QA in progress'
                    : phase.number <= AppConfig.implementedPhase
                    ? 'Included in this build'
                    : 'Planned',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final feature in phase.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $feature'),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
