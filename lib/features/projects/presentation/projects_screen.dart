import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/widgets/page_content.dart';
import '../data/local_project_repository.dart';
import '../domain/project_document.dart';
import '../domain/project_repository.dart';
import '../../ads/presentation/ads_widgets.dart';
import '../../ads/domain/ad_gateway.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});
  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _query = '';
  ProjectKind? _kind;
  Future<void> _delete(ProjectSummary project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${project.title}?'),
        content: const Text(
          'This removes this project and its imported copies from FrameLab. Gallery exports and original media stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(projectStoreProvider).delete(project.id);
      ref.invalidate(recentProjectsProvider);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete the project. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _rename(ProjectSummary project) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameProjectDialog(title: project.title),
    );
    if (title == null || title.isEmpty || !mounted) return;
    try {
      final store = ref.read(projectStoreProvider);
      final old = await store.load(project.id);
      if (old != null) {
        await store.save(
          ProjectDocument(
            id: old.id,
            kind: old.kind,
            title: title,
            createdAt: old.createdAt,
            updatedAt: DateTime.now().toUtc(),
            recipe: {...old.recipe, 'title': title},
            thumbnailPath: old.thumbnailPath,
          ),
        );
      }
      ref.invalidate(recentProjectsProvider);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not rename the project.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(recentProjectsProvider);
    final repository = ref.watch(projectRepositoryProvider);
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your projects',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Saved on your device. Ready when you are.'),
                  const SizedBox(height: 20),
                  TextField(
                    onChanged: (text) =>
                        setState(() => _query = text.toLowerCase()),
                    decoration: const InputDecoration(
                      labelText: 'Search projects',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _kind == null,
                        onSelected: (_) => setState(() => _kind = null),
                      ),
                      for (final kind in ProjectKind.values)
                        ChoiceChip(
                          label: Text(switch (kind) {
                            ProjectKind.photo => 'Photos',
                            ProjectKind.video => 'Videos',
                            ProjectKind.design => 'Designs',
                          }),
                          selected: _kind == kind,
                          onSelected: (_) => setState(() => _kind = kind),
                        ),
                    ],
                  ),
                  if (repository is LocalProjectRepository &&
                      repository.damagedProjectIds.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Some damaged projects could not be recovered. Their files have been kept; other projects remain available.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          value.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading projects',
                  ),
                ),
              ),
            ),
            error: (error, stack) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const InfoPanel(
                      title: 'Couldn’t load your projects',
                      body: 'Try again. Your media has not been changed.',
                    ),
                    FilledButton(
                      onPressed: () => ref.invalidate(recentProjectsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (projects) {
              final visible = projects
                  .where(
                    (p) =>
                        (_kind == null || p.kind == _kind) &&
                        p.title.toLowerCase().contains(_query),
                  )
                  .toList();
              if (visible.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        InfoPanel(
                          title: projects.isEmpty
                              ? 'A fresh canvas'
                              : 'No matching projects',
                          body: projects.isEmpty
                              ? 'Start a photo, video or template. Your edits save automatically as you work.'
                              : 'Try another search or project type.',
                          icon: Icons.folder_open_rounded,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => context.push('/photo'),
                          icon: const Icon(Icons.add),
                          label: const Text('New photo'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final project = visible[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        leading: project.thumbnailPath == null
                            ? Icon(
                                project.kind == ProjectKind.video
                                    ? Icons.movie_outlined
                                    : Icons.image_outlined,
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(project.thumbnailPath!),
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  cacheWidth: 160,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.image_outlined),
                                ),
                              ),
                        title: Text(
                          project.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${project.kind.name} · ${project.updatedAt.toLocal().toString().substring(0, 16)}',
                        ),
                        onTap: () => context.push('/edit/${project.id}'),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Project options',
                          onSelected: (action) => action == 'rename'
                              ? _rename(project)
                              : _delete(project),
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SliverToBoxAdapter(
            child: WorkspaceAdSlot(placement: AdPlacement.projects),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _RenameProjectDialog extends StatefulWidget {
  const _RenameProjectDialog({required this.title});
  final String title;

  @override
  State<_RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<_RenameProjectDialog> {
  late final _input = TextEditingController(text: widget.title);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename project'),
    content: TextField(
      controller: _input,
      maxLength: 100,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Project name'),
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
