import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Metadata only: the editor supplies a source-based, cached preview.
class FilterOption<T> {
  const FilterOption({
    required this.value,
    required this.label,
    required this.group,
  });
  final T value;
  final String label;
  final String group;
}

/// Shared offline filter browser. It never reads, decodes, or exports media.
class FilterStrip<T> extends StatefulWidget {
  const FilterStrip({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.previewBuilder,
    required this.intensity,
    required this.onIntensityChanged,
    required this.onIntensityChangeEnd,
    this.enabled = true,
    this.strengthEnabled = true,
  });
  final List<FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget Function(T) previewBuilder;
  final double intensity;
  final ValueChanged<double> onIntensityChanged;
  final VoidCallback onIntensityChangeEnd;
  final bool enabled;
  final bool strengthEnabled;

  @override
  State<FilterStrip<T>> createState() => _FilterStripState<T>();
}

class _FilterStripState<T> extends State<FilterStrip<T>> {
  String _group = 'All';

  @override
  Widget build(BuildContext context) {
    final groups = [
      'All',
      ...widget.options.map((o) => o.group).where((g) => g != 'All').toSet(),
    ];
    if (!groups.contains(_group)) _group = 'All';
    final options = widget.options
        .where((o) => _group == 'All' || o.group == _group)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: groups
                .map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(group),
                      selected: _group == group,
                      onSelected: (_) => setState(() => _group = group),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 116,
          child: ListView.separated(
            key: const ValueKey('filter-preview-strip'),
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final option = options[index];
              final selected = option.value == widget.selected;
              return Semantics(
                label: '${option.label} filter',
                button: true,
                selected: selected,
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: 86,
                    child: Material(
                      color: selected
                          ? AppColors.primary.withValues(alpha: .12)
                          : AppColors.surfaceRaised,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('filter-${option.label}'),
                        onTap: widget.enabled
                            ? () => widget.onSelected(option.value)
                            : null,
                        child: Column(
                          children: [
                            Expanded(
                              child: SizedBox.expand(
                                child: RepaintBoundary(
                                  child: widget.previewBuilder(option.value),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 40,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    option.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.text,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Strength'),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                key: const ValueKey('filter-strength'),
                value: widget.intensity.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                label: '${(widget.intensity * 100).round()}%',
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()} percent',
                onChanged: widget.enabled && widget.strengthEnabled
                    ? widget.onIntensityChanged
                    : null,
                onChangeEnd: widget.enabled && widget.strengthEnabled
                    ? (_) => widget.onIntensityChangeEnd()
                    : null,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '${(widget.intensity * 100).round()}%',
                textAlign: TextAlign.end,
                style: const TextStyle(color: AppColors.text),
              ),
            ),
          ],
        ),
        const Text(
          'Tap a look, then adjust its strength. All filters work offline.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}
