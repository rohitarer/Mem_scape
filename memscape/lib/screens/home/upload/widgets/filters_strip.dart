import 'package:flutter/material.dart';
import 'filters_presets.dart';

class FiltersStrip extends StatelessWidget {
  final List<FilterPreset> filters;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const FiltersStrip({
    super.key,
    required this.filters,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = filters[i];
          final selected = i == selectedIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    selected ? Colors.white.withOpacity(0.95) : Colors.black54,
                borderRadius: BorderRadius.circular(14),
                border:
                    selected
                        ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                        : null,
              ),
              child: Center(
                child: Text(
                  f.name,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
