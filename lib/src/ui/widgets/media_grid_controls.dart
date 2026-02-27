import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';

// ──────────────────────────────────────────────
// Enums
// ──────────────────────────────────────────────

enum SortField { dateAdded, name, size, fileType, random }

enum TypeFilter { all, image, gif, video, other }

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.dateAdded => 'Date Added',
        SortField.name => 'Name',
        SortField.size => 'Size',
        SortField.fileType => 'File Type',
        SortField.random => 'Random',
      };
}

extension TypeFilterLabel on TypeFilter {
  String get label => switch (this) {
        TypeFilter.all => 'All',
        TypeFilter.image => 'Image',
        TypeFilter.gif => 'GIF',
        TypeFilter.video => 'Video',
        TypeFilter.other => 'Other',
      };
}

// ──────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────

bool isGifPath(String relPath) =>
    p.extension(relPath).toLowerCase() == '.gif';

TypeFilter typeFilterOf(MediaItem item) {
  if (item.type == ItemType.video) return TypeFilter.video;
  if (item.type == ItemType.image) {
    if (isGifPath(item.storedRelPath)) return TypeFilter.gif;
    return TypeFilter.image;
  }
  return TypeFilter.other;
}

int fileTypeOrder(TypeFilter f) => switch (f) {
      TypeFilter.video => 0,
      TypeFilter.gif => 1,
      TypeFilter.image => 2,
      TypeFilter.other => 3,
      TypeFilter.all => 4,
    };

List<MediaItem> applyFiltersAndSort(
  List<MediaItem> items, {
  required SortField sortField,
  required bool sortAscending,
  required Set<TypeFilter> typeFilters,
  required int shuffleSeed,
}) {
  var result = items;

  if (typeFilters.isNotEmpty) {
    result =
        result.where((item) => typeFilters.contains(typeFilterOf(item))).toList();
  }

  result = List.of(result);
  if (sortField == SortField.random) {
    result.shuffle(Random(shuffleSeed));
  } else {
    result.sort((a, b) {
      int cmp;
      switch (sortField) {
        case SortField.dateAdded:
          cmp = a.createdAt.compareTo(b.createdAt);
        case SortField.name:
          cmp = a.originalName
              .toLowerCase()
              .compareTo(b.originalName.toLowerCase());
        case SortField.size:
          cmp = a.sizeBytes.compareTo(b.sizeBytes);
        case SortField.fileType:
          cmp = fileTypeOrder(typeFilterOf(a))
              .compareTo(fileTypeOrder(typeFilterOf(b)));
        case SortField.random:
          cmp = 0;
      }
      return sortAscending ? cmp : -cmp;
    });
  }

  return result;
}

// ──────────────────────────────────────────────
// SortButton
// ──────────────────────────────────────────────

class SortButton extends StatelessWidget {
  final String label;
  final SortField sortField;
  final bool sortAscending;
  final void Function(SortField field, bool ascending) onChanged;

  const SortButton({
    super.key,
    required this.label,
    required this.sortField,
    required this.sortAscending,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.sort, size: 16),
        label: Text('Sort: $label', style: const TextStyle(fontSize: 12)),
      ),
      menuChildren: [
        for (final field in SortField.values)
          MenuItemButton(
            leadingIcon: sortField == field && field != SortField.random
                ? Icon(
                    sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16)
                : sortField == field && field == SortField.random
                    ? const Icon(Icons.shuffle, size: 16)
                    : const SizedBox(width: 16),
            onPressed: () {
              if (field == SortField.random) {
                onChanged(field, false);
              } else if (sortField == field) {
                onChanged(field, !sortAscending);
              } else {
                onChanged(field, false);
              }
            },
            child: Text(field.label),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// TypeFilterButton
// ──────────────────────────────────────────────

class TypeFilterButton extends StatelessWidget {
  final String label;
  final Set<TypeFilter> selected;
  final void Function(Set<TypeFilter>) onChanged;

  const TypeFilterButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.filter_list, size: 16),
        label: Text('Filter: $label', style: const TextStyle(fontSize: 12)),
        style: selected.isNotEmpty
            ? OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary)
            : null,
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: selected.isEmpty
              ? const Icon(Icons.check, size: 16)
              : const SizedBox(width: 16),
          onPressed: () => onChanged({}),
          child: const Text('All'),
        ),
        const Divider(height: 1),
        for (final filter in [
          TypeFilter.image,
          TypeFilter.gif,
          TypeFilter.video,
          TypeFilter.other
        ])
          MenuItemButton(
            leadingIcon: selected.contains(filter)
                ? Icon(Icons.check,
                    size: 16, color: Theme.of(context).colorScheme.primary)
                : const SizedBox(width: 16),
            onPressed: () {
              final next = Set<TypeFilter>.from(selected);
              if (next.contains(filter)) {
                next.remove(filter);
              } else {
                next.add(filter);
              }
              onChanged(next);
            },
            child: Text(filter.label),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// TypeBadge
// ──────────────────────────────────────────────

class TypeBadge extends StatelessWidget {
  final MediaItem item;
  final bool isGif;
  final bool hasThumb;

  const TypeBadge({
    super.key,
    required this.item,
    required this.isGif,
    required this.hasThumb,
  });

  @override
  Widget build(BuildContext context) {
    if (item.type == ItemType.video) {
      if (!hasThumb) return const SizedBox.shrink();
      return _badge(
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_arrow, size: 14, color: Colors.white),
          SizedBox(width: 2),
          Text('Video',
              style: TextStyle(color: Colors.white, fontSize: 10)),
        ]),
      );
    }
    if (isGif) {
      return _badge(
        child: const Text('GIF',
            style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );
    }
    if (item.type == ItemType.image) {
      return _badge(
        child:
            const Text('Image', style: TextStyle(color: Colors.white, fontSize: 10)),
      );
    }
    return _badge(
      child:
          const Text('Other', style: TextStyle(color: Colors.white, fontSize: 10)),
    );
  }

  Widget _badge({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}
