import 'package:flutter/material.dart';
import '../models/breadcrumb.dart';

/// AppBar text translated text translated text text
/// P003 § 2-3 text: breadcrumb_path server text translated text translated text.
/// translated text text(current text)text text text.
class BreadcrumbNav extends StatelessWidget {
  final List<Breadcrumb> breadcrumbs;

  /// text firsttext text displaytext storage name translated text
  final String storageLabel;

  /// translated text text text text. text translated text nodeUuidtext text (null = text).
  final void Function(String? nodeUuid) onBreadcrumbTapped;

  const BreadcrumbNav({
    super.key,
    required this.breadcrumbs,
    required this.storageLabel,
    required this.onBreadcrumbTapped,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: _buildItems(context),
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    final items = <Widget>[];

    // storage text (text text firsttext text)
    final bool hasSubCrumbs = breadcrumbs.isNotEmpty;
    items.add(
      GestureDetector(
        onTap: () => onBreadcrumbTapped(null),
        child: Text(
          storageLabel,
          style: TextStyle(
            fontSize: 13,
            color: hasSubCrumbs
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: hasSubCrumbs ? FontWeight.normal : FontWeight.bold,
          ),
        ),
      ),
    );

    if (hasSubCrumbs) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            Icons.chevron_right,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    for (var i = 0; i < breadcrumbs.length; i++) {
      final crumb = breadcrumbs[i];
      final isLast = i == breadcrumbs.length - 1;

      items.add(
        GestureDetector(
          onTap: isLast ? null : () => onBreadcrumbTapped(crumb.nodeUuid),
          child: Text(
            crumb.name,
            style: TextStyle(
              fontSize: 13,
              color: isLast
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.primary,
              fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );

      if (!isLast) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }
    }
    return items;
  }
}
