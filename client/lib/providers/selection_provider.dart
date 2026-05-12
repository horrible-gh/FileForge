import 'package:flutter/foundation.dart';

/// D003 M01~M05 — 다중 선택 모드 상태 관리
class SelectionProvider extends ChangeNotifier {
  bool _isSelectionMode = false;
  final Set<String> _selectedUuids = {};

  // ── 읽기 전용 ─────────────────────────────────────────────────────────────
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedUuids => Set.unmodifiable(_selectedUuids);
  int get selectedCount => _selectedUuids.length;
  bool get hasSelection => _selectedUuids.isNotEmpty;

  bool isSelected(String nodeUuid) => _selectedUuids.contains(nodeUuid);

  // ── 선택 모드 진입/해제 ───────────────────────────────────────────────────

  void enterSelectionMode([String? initialNodeUuid]) {
    _isSelectionMode = true;
    if (initialNodeUuid != null) {
      _selectedUuids.add(initialNodeUuid);
    }
    notifyListeners();
  }

  void exitSelectionMode() {
    _isSelectionMode = false;
    _selectedUuids.clear();
    notifyListeners();
  }

  // ── 선택 토글 ─────────────────────────────────────────────────────────────

  void toggle(String nodeUuid) {
    if (_selectedUuids.contains(nodeUuid)) {
      _selectedUuids.remove(nodeUuid);
      if (_selectedUuids.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedUuids.add(nodeUuid);
    }
    notifyListeners();
  }

  // ── 전체 선택 ─────────────────────────────────────────────────────────────

  void selectAll(List<String> allUuids) {
    _selectedUuids.addAll(allUuids);
    notifyListeners();
  }

  void deselectAll() {
    _selectedUuids.clear();
    notifyListeners();
  }
}
