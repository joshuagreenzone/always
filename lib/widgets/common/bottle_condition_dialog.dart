import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/bottle_condition.dart';
import '../../services/bottle_condition_service.dart';

/// Returns false when the bottle should be skipped. State updates are saved
/// immediately, independently of the temporary scan batch.
Future<bool> checkBottleConditionForScan({
  required BuildContext context,
  required int accId,
  required String bottleNumber,
  bool allowUnregistered = false,
  bool allowDamagedPickup = false,
  bool requireRecoveryRefill = false,
  String damagedActionLabel = 'Pick Up Damaged Bottle',
  BottleConditionService? service,
  BottleCondition? initialCondition,
}) async {
  final conditionService = service ?? BottleConditionService();
  final bottle =
      initialCondition ??
      await conditionService.getCondition(
        accId: accId,
        bottleNumber: bottleNumber,
        allowUnregistered: allowUnregistered,
      );
  if (!context.mounted) return false;
  if (bottle == null) return true;
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('${bottle.bottleNumber} · ${bottle.ownerLabel}'),
      duration: const Duration(seconds: 2),
    ),
  );
  if (bottle.isHealthy) {
    if (requireRecoveryRefill && bottle.needsRefillAfterRecovery) {
      throw Exception(
        'Bottle ${bottle.bottleNumber} was restored to healthy. Refill it again before delivery.',
      );
    }
    return true;
  }

  final updated = await showDialog<BottleCondition>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BottleConditionDialog(
      bottle: bottle,
      accId: accId,
      service: conditionService,
      allowDamagedPickup: allowDamagedPickup,
      requireRecoveryRefill: requireRecoveryRefill,
      damagedActionLabel: damagedActionLabel,
    ),
  );
  if (updated == null) return false;
  return (updated.isHealthy &&
          !(requireRecoveryRefill && updated.needsRefillAfterRecovery)) ||
      (allowDamagedPickup && updated.condition == 'DAMAGED');
}

class BottleConditionDialog extends StatefulWidget {
  final BottleCondition bottle;
  final int accId;
  final BottleConditionService service;
  final bool allowDamagedPickup;
  final bool requireRecoveryRefill;
  final String damagedActionLabel;

  const BottleConditionDialog({
    super.key,
    required this.bottle,
    required this.accId,
    required this.service,
    this.allowDamagedPickup = false,
    this.requireRecoveryRefill = false,
    this.damagedActionLabel = 'Pick Up Damaged Bottle',
  });

  @override
  State<BottleConditionDialog> createState() => _BottleConditionDialogState();
}

class _BottleConditionDialogState extends State<BottleConditionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  String _condition = 'HEALTHY';
  bool _isSaving = false;
  String? _error;
  BottleCondition? _saved;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final saved = await widget.service.updateCondition(
        accId: widget.accId,
        bottle: widget.bottle,
        condition: _condition,
        note: _noteController.text,
      );
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  String _dateLabel(DateTime date) =>
      DateFormat('MMM d, yyyy h:mm:ss a').format(date);

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        title: Text(
          saved == null
              ? 'Bottle ${widget.bottle.condition.toLowerCase()}'
              : 'Bottle State Updated',
        ),
        content: SingleChildScrollView(
          child: saved != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Bottle: ${saved.bottleNumber}'),
                    Text('Owner: ${saved.ownerLabel}'),
                    Text('State: ${saved.condition}'),
                    if (saved.updatedAt != null)
                      Text(
                        'Updated: ${_dateLabel(saved.updatedAt!)} (server time)',
                      ),
                    Text('Note: ${saved.note ?? _noteController.text.trim()}'),
                    const SizedBox(height: 12),
                    Text(
                      saved.isHealthy
                          ? saved.needsRefillAfterRecovery
                                ? 'Refill this bottle again before delivery.'
                                : 'Continue scanning this bottle.'
                          : widget.allowDamagedPickup &&
                                saved.condition == 'DAMAGED'
                          ? 'This damaged bottle can be ${widget.damagedActionLabel.startsWith('Return') ? 'returned to the station' : 'picked up'}. Refill and delivery remain blocked.'
                          : 'This bottle will be skipped while it is ${saved.condition.toLowerCase()}.',
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bottle ${widget.bottle.bottleNumber} is marked ${widget.bottle.condition.toLowerCase()}.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.allowDamagedPickup &&
                                widget.bottle.condition == 'DAMAGED'
                            ? 'You can ${widget.damagedActionLabel.startsWith('Return') ? 'return' : 'pick up'} this bottle while keeping it damaged. Refill and delivery remain blocked.'
                            : 'Review its condition before continuing. You can update its state or skip this bottle.',
                      ),
                      if (widget.bottle.updatedAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Last updated: ${_dateLabel(widget.bottle.updatedAt!)} (server time)',
                        ),
                      ],
                      if (widget.bottle.note != null)
                        Text('Last note: ${widget.bottle.note}'),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _condition,
                        decoration: const InputDecoration(
                          labelText: 'New state',
                        ),
                        items: BottleCondition.states
                            .where((state) => state != widget.bottle.condition)
                            .map(
                              (state) => DropdownMenuItem(
                                value: state,
                                child: Text(state),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _condition = value!),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteController,
                        enabled: !_isSaving,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Note (required)',
                          hintText: 'Explain why the bottle state is changing',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a note before saving.'
                            : null,
                      ),
                      const Text(
                        'The state, note, staff member, and update date are saved immediately, even if you later discard the scan batch.',
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        actions: saved != null
            ? [
                FilledButton(
                  onPressed: () => Navigator.pop(context, saved),
                  child: const Text('OK'),
                ),
              ]
            : [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Skip Bottle'),
                ),
                if (widget.allowDamagedPickup &&
                    widget.bottle.condition == 'DAMAGED')
                  TextButton(
                    onPressed: _isSaving || _error != null
                        ? null
                        : () => Navigator.pop(context, widget.bottle),
                    child: Text(widget.damagedActionLabel),
                  ),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(_isSaving ? 'Saving...' : 'Save State'),
                ),
              ],
      ),
    );
  }
}
