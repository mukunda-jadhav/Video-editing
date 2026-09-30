import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';

import '../../../core/theme/app_theme.dart';
import 'widgets/template_art.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onCreatePhoto,
    required this.onCreateVideo,
    required this.onViewProjects,
    required this.onViewTemplates,
    required this.onViewPremium,
    required this.onViewSettings,
  });

  final VoidCallback onCreatePhoto;
  final VoidCallback onCreateVideo;
  final VoidCallback onViewProjects;
  final VoidCallback onViewTemplates;
  final VoidCallback onViewPremium;
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
            constraints: const BoxConstraints(maxWidth: 1048),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrandHeader(onViewPremium: onViewPremium),
                  const SizedBox(height: 28),
                  const _CreativeHero(),
                  const SizedBox(height: 28),
                  _CreateActions(
                    onPhoto: onCreatePhoto,
                    onVideo: onCreateVideo,
                  ),
                  const SizedBox(height: 30),
                  _SectionHeading(
                    title: 'Find your starting point',
                    action: 'Explore',
                    onTap: onViewTemplates,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Editable templates · Made to become yours',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _TemplateStrip(onViewTemplates: onViewTemplates),
                  const SizedBox(height: 28),
                  _SectionHeading(
                    title: 'Your projects',
                    action: 'View all',
                    onTap: onViewProjects,
                  ),
                  const SizedBox(height: 12),
                  if (projects.isEmpty)
                    _ProjectsEmptyState(onCreatePhoto: onCreatePhoto)
                  else ...[
                    for (final project in projects.take(3))
                      Card(
                        child: ListTile(
                          leading: project.thumbnailPath == null
                              ? const Icon(Icons.layers_outlined)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(project.thumbnailPath!),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    cacheWidth: 128,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.layers_outlined),
                                  ),
                                ),
                          title: Text(
                            project.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(project.kind.name),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.push('/edit/${project.id}'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),
                  _BuildNote(onViewSettings: onViewSettings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onViewPremium});
  final VoidCallback onViewPremium;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.crop_free_rounded,
                    color: AppColors.onPrimary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'FrameLab',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(letterSpacing: -.8),
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: onViewPremium,
            icon: const Icon(Icons.auto_awesome_outlined, size: 17),
            label: const Text('PRO'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              backgroundColor: AppColors.accent.withValues(alpha: .06),
              side: BorderSide(color: AppColors.accent.withValues(alpha: .3)),
              minimumSize: const Size(88, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreativeHero extends StatelessWidget {
  const _CreativeHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 7,
              runSpacing: 4,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.offline_bolt_outlined,
                    color: AppColors.accent,
                    size: 16,
                  ),
                ),
                Text(
                  'ON YOUR DEVICE. IN YOUR FLOW.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              'A little idea.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            Text(
              'A great creation.',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            const Text(
              'Make something that feels like you.\nYour creative space. No account needed.',
            ),
          ],
        );
        if (!wide) return content;
        return Row(
          children: [
            Expanded(flex: 3, child: content),
            const SizedBox(width: 32),
            Flexible(
              flex: 2,
              child: ExcludeSemantics(
                child: Transform.rotate(
                  angle: -.065,
                  child: AspectRatio(
                    aspectRatio: 1.4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: const TemplateArt(style: TemplateArtStyle.studio),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CreateActions extends StatelessWidget {
  const _CreateActions({required this.onPhoto, required this.onVideo});
  final VoidCallback onPhoto;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 312 ||
            MediaQuery.textScalerOf(context).scale(16) > 21.6;
        final photo = _CreateCard(
          title: 'New photo',
          subtitle: 'From everyday to eye-catching',
          icon: Icons.add_photo_alternate_outlined,
          color: AppColors.primary,
          onTap: onPhoto,
        );
        final video = _CreateCard(
          title: 'New video',
          subtitle: 'Little moments. Big stories.',
          icon: Icons.video_library_outlined,
          color: AppColors.accent,
          onTap: onVideo,
        );
        if (stacked) {
          return Column(children: [photo, const SizedBox(height: 12), video]);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: photo),
              const SizedBox(width: 12),
              Expanded(child: video),
            ],
          ),
        );
      },
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 23),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.north_east_rounded,
                      size: 19,
                      color: AppColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.action,
    required this.onTap,
  });
  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final large = MediaQuery.textScalerOf(context).scale(16) > 21.6;
        final heading = Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        );
        final button = TextButton(onPressed: onTap, child: Text(action));
        if (large || constraints.maxWidth < 312) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, button],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 8),
            button,
          ],
        );
      },
    );
  }
}

class _TemplateStrip extends StatelessWidget {
  const _TemplateStrip({required this.onViewTemplates});
  final VoidCallback onViewTemplates;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A horizontal, intrinsically sized row accommodates large text without
        // squeezing labels or imposing a fragile fixed list height.
        final tileWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 28) / 3
            : 164.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TemplateTile(
                  width: tileWidth,
                  title: 'Make it yours',
                  category: 'Instagram post',
                  style: TemplateArtStyle.studio,
                  onTap: onViewTemplates,
                ),
                const SizedBox(width: 14),
                _TemplateTile(
                  width: tileWidth,
                  title: 'Weekend journal',
                  category: 'Story & reel',
                  style: TemplateArtStyle.weekend,
                  onTap: onViewTemplates,
                ),
                const SizedBox(width: 14),
                _TemplateTile(
                  width: tileWidth,
                  title: 'Daily essentials',
                  category: 'Product ad',
                  style: TemplateArtStyle.product,
                  onTap: onViewTemplates,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.width,
    required this.title,
    required this.category,
    required this.style,
    required this.onTap,
  });
  final double width;
  final String title;
  final String category;
  final TemplateArtStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label:
            '$title template preview, $category. Tap to browse and edit templates.',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(aspectRatio: 1, child: TemplateArt(style: style)),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          category,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onTap),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectsEmptyState extends StatelessWidget {
  const _ProjectsEmptyState({required this.onCreatePhoto});
  final VoidCallback onCreatePhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.layers_outlined, color: AppColors.muted, size: 30),
          const SizedBox(height: 12),
          Text(
            'Every great edit starts somewhere.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Your creations are saved here automatically. Start with a photo, video or template.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onCreatePhoto,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Start your first creation'),
          ),
        ],
      ),
    );
  }
}

class _BuildNote extends StatelessWidget {
  const _BuildNote({required this.onViewSettings});
  final VoidCallback onViewSettings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onViewSettings,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.construction_outlined,
                    color: AppColors.muted,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your studio. Your files.',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Offline editing · Settings and privacy',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
