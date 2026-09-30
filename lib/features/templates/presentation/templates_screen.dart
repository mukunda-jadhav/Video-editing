import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/template_catalog.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  String _category = 'All';
  Future<void> _open(StudioTemplate template) async {
    if (mounted) {
      await context.push(
        '${template.video ? '/video' : '/photo'}?template=${template.id}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'All',
      ...templateCatalog.map((t) => t.category).toSet(),
    ];
    final visible = templateCatalog
        .where((t) => _category == 'All' || t.category == _category)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Find your starting point')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  'Your words. Your images. Your look. Every layer is editable.',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: category == _category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final columns = scale > 1.5
                      ? 1
                      : (constraints.crossAxisExtent / 230).floor().clamp(1, 4);
                  return SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final template = visible[index];
                      return Semantics(
                        button: true,
                        label:
                            '${template.title}, ${template.category}, editable template',
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _open(template),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: TemplatePreview(template: template),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        template.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        template.video ? 'VIDEO' : 'DESIGN',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }, childCount: visible.length),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      mainAxisExtent: scale > 1.5 ? 470 : 330,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uses the same layer recipe as editing; no downloaded template artwork.
class TemplatePreview extends StatelessWidget {
  const TemplatePreview({super.key, required this.template});
  final StudioTemplate template;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ColoredBox(
      color: Color(template.background),
      child: Center(
        child: AspectRatio(
          aspectRatio: template.width / template.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth,
                  height = constraints.maxHeight;
              final layers = template.photoRecipe['layers'] as List<dynamic>;
              return ClipRect(
                child: Stack(
                  children: [
                    for (final value in layers)
                      _layer(
                        Map<String, dynamic>.from(value as Map),
                        width,
                        height,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget _layer(Map<String, dynamic> layer, double width, double height) {
    final kind = layer['kind'];
    return Positioned(
      left: (layer['x'] as num).toDouble() * width,
      top: (layer['y'] as num).toDouble() * height,
      width: (layer['width'] as num).toDouble() * width,
      height: (layer['height'] as num).toDouble() * height,
      child: kind == 'text'
          ? Text(
              layer['text'] as String,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: layer['fontFamily'] as String,
                color: Color(layer['color'] as int),
                fontSize: (layer['fontSize'] as num).toDouble() * width,
                fontWeight: layer['bold'] == true
                    ? FontWeight.w700
                    : FontWeight.w400,
                height: 1.08,
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: Color(layer['color'] as int),
                shape: kind == 'circle' ? BoxShape.circle : BoxShape.rectangle,
              ),
            ),
    );
  }
}
