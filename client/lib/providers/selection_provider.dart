import 'package:flutter/foundation.dart';

/// D003 M01~M05 — text selection text state management
class SelectionProvider extends ChangeNotifier {
  bool _isSelectionMode = false;
  final Set<String> _selectedUuids = {};

  // ── read-only ─────────────────────────────────────────────────────────────
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedUuids => Set.unmodifiable(_selectedUuids);
  int get selectedCount => _selectedUuids.length;
  bool get hasSelection => _selectedUuids.isNotEmpty;

  bool isSelected(String nodeUuid) => _selectedUuids.contains(nodeUuid);

  // ── selection text text/text ───────────────────────────────────────────────────

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

  // ── selection text ─────────────────────────────────────────────────────────────

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

  // ── text selection ─────────────────────────────────────────────────────────────

  void selectAll(List<String> allUuids) {
    _selectedUuids.addAll(allUuids);
    notifyListeners();
  }

  void deselectAll() {
    _selectedUuids.clear();
    notifyListeners();
  }
}
