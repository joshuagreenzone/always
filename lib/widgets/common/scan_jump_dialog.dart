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
  final reason = await showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.viewInsetsOf(dialogContext).bottom +
              MediaQuery.paddingOf(dialogContext).bottom +
              20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'A step was skipped',
                style: TextStyle(
                  color: Color(0xFF075578),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Bottle $bottleNumber was not scanned at ${_scanLabel(transition['expectedPreviousEventType'])}. Tell us why you are continuing.',
                style: const TextStyle(color: Color(0xFF71869A), fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                'Reason (required)',
                style: TextStyle(color: Color(0xFF71869A), fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                maxLength: 1000,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) => setDialogState(() => reasonText = value),
                decoration: InputDecoration(
                  hintText: 'Explain the missed scan',
                  counterText: '',
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD7E7F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD7E7F0)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF087DA9),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: reasonText.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, reasonText.trim()),
                child: const Text('Continue'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF087DA9),
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: Color(0xFF73BADD)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel scan'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (reason == null) return null;
  return {...transition, 'jumpReason': reason};
}
