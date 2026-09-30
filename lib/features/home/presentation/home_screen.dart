import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/projects/domain/project_repository.dart';
import 'widgets/template_art.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onCreatePhoto,
    required this.onCreateVideo,
    required this.onViewProjects,
    required this.onViewTemplates,
    required this.onViewSettings,
  });
  final VoidCallback onCreatePhoto;
  final VoidCallback onCreateVideo;
  final VoidCallback onViewProjects;
  final VoidCallback onViewTemplates;
  final VoidCallback onViewSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(recentProjectsProvider).asData?.value ?? [];
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        key: const PageStorageKey('home-scroll'),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.movie_edit,
                        size: 28,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'FrameLab',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: onViewSettings,
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _NewProject(onTap: onCreateVideo),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final large =
                          MediaQuery.textScalerOf(context).scale(14) > 22;
                      final actions = [
                        _QuickAction(
                          icon: Icons.add_photo_alternate_outlined,
                          title: 'New photo',
                          onTap: onCreatePhoto,
                        ),
                        _QuickAction(
                          icon: Icons.video_library_outlined,
                          title: 'New video',
                          onTap: onCreateVideo,
                        ),
                        _QuickAction(
                          icon: Icons.dashboard_customize_outlined,
                          title: 'Templates',
                          onTap: onViewTemplates,
                        ),
                      ];
                      if (large || constraints.maxWidth < 280) {
                        return Column(
                          children: [
                            for (final action in actions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: action,
                              ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(child: actions[i]),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  _Heading(
                    title: 'Your projects',
                    action: 'View all',
                    onTap: onViewProjects,
                  ),
                  const SizedBox(height: 12),
                  if (projects.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 30,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.video_collection_outlined,
                            color: AppColors.muted,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Your next edit starts here',
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Create a project. Pick your clips. Make it yours.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    for (final project in projects.take(5))
                      _ProjectRow(
                        project: project,
                        onTap: () => context.push('/edit/${project.id}'),
                      ),
                  ],
                  const SizedBox(height: 26),
                  _Heading(
                    title: 'Start with a template',
                    action: 'Explore',
                    onTap: onViewTemplates,
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in const [
                          ('Social post', TemplateArtStyle.studio),
                          ('Story', TemplateArtStyle.weekend),
                          ('Thumbnail', TemplateArtStyle.product),
                        ]) ...[
                          _TemplatePreview(
                            title: item.$1,
                            style: item.$2,
                            onTap: onViewTemplates,
                          ),
                          const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Icon(
                        Icons.offline_bolt_outlined,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All tools free. Your media stays on your device.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewProject extends StatelessWidget {
  const _NewProject({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.accent,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.onAccent.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 34,
                color: AppColors.onAccent,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New project',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.onAccent),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Turn your clips into a story',
                    style: TextStyle(color: AppColors.onAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.onAccent),
          ],
        ),
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        child: Column(
          children: [
            Icon(icon, size: 26, color: AppColors.text),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.action,
    required this.onTap,
  });
  final String title, action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(width: 8),
      TextButton(onPressed: onTap, child: Text(action)),
    ],
  );
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.onTap});
  final ProjectSummary project;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 70,
                  height: 60,
                  child: project.thumbnailPath == null
                      ? ColoredBox(
                          color: AppColors.surfaceRaised,
                          child: Icon(
                            project.kind == ProjectKind.video
                                ? Icons.movie_outlined
                                : Icons.photo_outlined,
                            color: AppColors.muted,
                          ),
                        )
                      : Image.file(
                          File(project.thumbnailPath!),
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: AppColors.surfaceRaised,
                            child: Icon(
                              Icons.image_outlined,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${project.kind.name} · Saved locally',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({
    required this.title,
    required this.style,
    required this.onTap,
  });
  final String title;
  final TemplateArtStyle style;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 156,
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 108,
              child: ExcludeSemantics(child: TemplateArt(style: style)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
