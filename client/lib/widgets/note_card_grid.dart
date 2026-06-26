import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/node.dart';
import '../providers/selection_provider.dart';
import '../widgets/empty_state.dart';
import 'note_card.dart';

/// note storage text 2text translated text text.
/// - textselectiontext translated text text: AddNoteCard (+translated text + "text text")
/// - selectiontext: AddNoteCard text
/// - empty state: EmptyState + "text text translated text" text
class NoteCardGrid extends StatelessWidget {
  final List<Node> children;
  final void Function(Node node) onNoteTap;
  final void Function(Node node) onFolderTap;
  final VoidCallback onAddNote;
  final void Function(Node node) onRename;
  final void Function(Node node) onDelete;

  const NoteCardGrid({
    super.key,
    required this.children,
    required this.onNoteTap,
    required this.onFolderTap,
    required this.onAddNote,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cardAspectRatio =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? 1.39
            : 1.5;

    if (children.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EmptyState(
            message: 'No notes',
            icon: Icons.note_outlined,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onAddNote,
            child: const Text('Create New Note'),
          ),
        ],
      );
    }

    return Consumer<SelectionProvider>(
      builder: (context, selProv, _) {
        final showAddCard = !selProv.isSelectionMode;
        final itemCount =
            showAddCard ? children.length + 1 : children.length;

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: cardAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (showAddCard && index == children.length) {
              return _AddNoteCard(onTap: onAddNote);
            }
            final node = children[index];
            final isSelected =
                node.nodeUuid != null && selProv.isSelected(node.nodeUuid!);
            return NoteCard(
              node: node,
              isSelectionMode: selProv.isSelectionMode,
              isSelected: isSelected,
              onTap: () {
                if (selProv.isSelectionMode) {
                  if (node.nodeUuid != null) {
                    selProv.toggle(node.nodeUuid!);
                  }
                } else if (node.isFolder) {
                  onFolderTap(node);
                } else {
                  onNoteTap(node);
                }
              },
              onLongPress: () {
                if (node.nodeUuid != null) {
                  selProv.enterSelectionMode(node.nodeUuid!);
                }
              },
              onRename: () => onRename(node),
              onDelete: () => onDelete(node),
            );
          },
        );
      },
    );
  }
}

class _AddNoteCard extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddNoteCard({this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 32, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'New Note',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
