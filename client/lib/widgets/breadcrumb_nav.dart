import 'package:flutter/material.dart';
import '../models/breadcrumb.dart';

/// AppBar 하단 빵부스러기 네비게이션 위젯
/// P003 § 2-3 기준: breadcrumb_path 서버 응답 순서대로 렌더링.
/// 마지막 항목(현재 위치)은 탭 불가.
class BreadcrumbNav extends StatelessWidget {
  final List<Breadcrumb> breadcrumbs;

  /// 맨 앞에 항상 표시되는 스토리지 이름 레이블
  final String storageLabel;

  /// 빵부스러기 탭 시 호출. 해당 항목의 nodeUuid를 전달 (null = 루트).
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

    // 스토리지 항목 (항상 맨 앞에 고정)
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
