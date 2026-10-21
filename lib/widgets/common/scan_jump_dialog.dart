import 'package:flutter/material.dart';

import '../../services/scan_transition_service.dart';

String _scanLabel(Object? type) => switch (type) {
  'REFILL_SCAN' => 'refill',
  'LOAD_SCAN' => 'load for delivery',
  'DELIVERY_SCAN' => 'delivery',
  'PICKUP_SCAN' => 'pickup',
  'UNLOAD_SCAN' => 'return to station',
  _ => 'no previous scan',
};

Future<Map<String, dynamic>?> checkScanJump({
  required BuildContext context,
  required String bottleNumber,
  required String eventType,
  ScanTransitionService? service,
  Map<String, dynamic>? initialTransition,
}) async {
  final transition =
      initialTransition ??
      await (service ?? ScanTransitionService()).check(bottleNumber, eventType);
  if (!context.mounted) return null;
  if (transition['isCycleJump'] != true) return transition;

  var reasonText = '';
  final reason = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Explain scan jump'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bottle $bottleNumber was last scanned at '
              '${_scanLabel(transition['previousEventType'])}. '
              'Expected: ${_scanLabel(transition['expectedPreviousEventType'])}.',
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              maxLength: 1000,
              maxLines: 3,
              onChanged: (value) => setDialogState(() => reasonText = value),
              decoration: const InputDecoration(
                labelText: 'Why is this step being skipped?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: reasonText.trim().isEmpty
                ? null
                : () => Navigator.pop(dialogContext, reasonText.trim()),
            child: const Text('Continue Scan'),
          ),
        ],
      ),
    ),
  );
  if (reason == null) return null;
  return {...transition, 'jumpReason': reason};
}
