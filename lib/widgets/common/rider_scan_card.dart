import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Shared card spacing for rider scanning workflows.
class RiderScanCard extends StatelessWidget {
  final List<Widget> children;
  const RiderScanCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class PendingBottleList extends StatelessWidget {
  final String title;
  final List<String> bottles;
  final ValueChanged<String>? onRemove;

  const PendingBottleList({
    super.key,
    required this.title,
    required this.bottles,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) => RiderScanCard(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Not saved yet. Confirm below when you finish.'),
      if (bottles.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('No bottles scanned yet.'),
        ),
      ...bottles.map(
        (number) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
          ),
          title: Text(number),
          subtitle: const Text('Ready to confirm'),
          trailing: onRemove == null
              ? null
              : IconButton(
                  tooltip: 'Remove $number from scanned list',
                  onPressed: () => onRemove!(number),
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
    ],
  );
}
