import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/upload_item.dart';
import '../providers/upload_provider.dart';

/// D003 U04~U07 — 하단 업로드 진행률 패널
class UploadPanel extends StatelessWidget {
  const UploadPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UploadProvider>();
    if (!provider.hasItems) return const SizedBox.shrink();

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, provider),
          if (provider.isPanelExpanded) _buildItemList(context, provider),
          if (bottomInset > 0) SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UploadProvider provider) {
    final uploading = provider.uploadingCount;
    final total = provider.items.length;
    final completed = provider.completedCount;

    String statusText;
    if (uploading > 0) {
      statusText = 'Uploading ($completed/$total)';
    } else if (provider.pendingCount > 0) {
      statusText = 'Waiting ($completed/$total)';
    } else {
      statusText = 'Upload Complete ($completed/$total)';
    }

    return InkWell(
      onTap: provider.togglePanel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              provider.isPanelExpanded
                  ? Icons.expand_more
                  : Icons.expand_less,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusText,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            if (provider.canClearAll)
              TextButton(
                onPressed: provider.clearCompleted,
                child: const Text('Clear All', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemList(BuildContext context, UploadProvider provider) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: provider.items.length,
        itemBuilder: (ctx, index) {
          final item = provider.items[index];
          return _buildItemRow(context, item, provider);
        },
      ),
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    UploadItem item,
    UploadProvider provider,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildStatusIcon(item),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.filename,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.status == UploadStatus.uploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 3,
                    ),
                  ),
                if (item.status == UploadStatus.uploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${(item.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                if (item.status == UploadStatus.error &&
                    item.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.errorMessage!,
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ),
                if (item.status == UploadStatus.pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Waiting',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => provider.removeItem(item.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(UploadItem item) {
    switch (item.status) {
      case UploadStatus.pending:
        return const Icon(Icons.schedule, size: 18, color: Colors.grey);
      case UploadStatus.uploading:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UploadStatus.completed:
        return const Icon(Icons.check_circle, size: 18, color: Colors.green);
      case UploadStatus.error:
        return const Icon(Icons.error, size: 18, color: Colors.red);
    }
  }
}
