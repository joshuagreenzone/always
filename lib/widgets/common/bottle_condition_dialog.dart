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

  final updated = await showModalBottomSheet<BottleCondition>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
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
  final Set<int> _repairSupplyIds = {};
  bool _isSaving = false;
  String? _error;
  BottleCondition? _saved;

  @override
  void initState() {
    super.initState();
    _condition = widget.bottle.isHealthy ? 'DAMAGED' : 'HEALTHY';
  }

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
        repairSupplyIds:
            widget.bottle.condition == 'DAMAGED' && _condition == 'HEALTHY'
            ? _repairSupplyIds.toList()
            : const [],
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
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom +
              20,
        ),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFF71869A), fontSize: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  saved == null ? 'Bottle condition' : 'Bottle State Updated',
                  style: const TextStyle(
                    color: Color(0xFF075578),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                saved != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Bottle: ${saved.bottleNumber}'),
                          Text('Owner: ${saved.ownerLabel}'),
                          Text('State: ${saved.condition}'),
                          if (saved.partsUsed > 0)
                            Text(
                              'Replacement parts used: ${saved.partsUsed} piece(s).',
                            ),
                          if (saved.updatedAt != null)
                            Text(
                              'Updated: ${_dateLabel(saved.updatedAt!)} (server time)',
                            ),
                          Text(
                            'Note: ${saved.note ?? _noteController.text.trim()}',
                          ),
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
                                  : 'Choose its condition and add a required note.',
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
                            Row(
                              children: [
                                for (final state in BottleCondition.states) ...[
                                  if (state != BottleCondition.states.first)
                                    const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _condition == state
                                            ? const Color(0xFF087DA9)
                                            : Colors.white,
                                        foregroundColor: _condition == state
                                            ? Colors.white
                                            : const Color(0xFF075578),
                                        minimumSize: const Size.fromHeight(42),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFD7E7F0),
                                          ),
                                        ),
                                      ),
                                      onPressed:
                                          _isSaving ||
                                              state == widget.bottle.condition
                                          ? null
                                          : () => setState(
                                              () => _condition = state,
                                            ),
                                      child: Text(
                                        '${state[0]}${state.substring(1).toLowerCase()}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (widget.bottle.condition == 'DAMAGED' &&
                                _condition == 'HEALTHY') ...[
                              const Text(
                                'Caps or spigots used (optional)',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Text(
                                'Select any caps or spigots used to repair this bottle. One piece per selected part will be deducted from inventory. Refill seals are separate.',
                              ),
                              for (final part in widget.bottle.repairParts)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(part.name),
                                  subtitle: Text(
                                    '${part.quantityOnHand} in stock',
                                  ),
                                  value: _repairSupplyIds.contains(
                                    part.supplyId,
                                  ),
                                  onChanged:
                                      _isSaving || part.quantityOnHand < 1
                                      ? null
                                      : (selected) => setState(() {
                                          if (selected == true) {
                                            _repairSupplyIds.add(part.supplyId);
                                          } else {
                                            _repairSupplyIds.remove(
                                              part.supplyId,
                                            );
                                          }
                                        }),
                                ),
                              if (widget.bottle.repairParts.isEmpty)
                                const Text(
                                  'No compatible replacement parts are configured.',
                                ),
                              const SizedBox(height: 12),
                            ],
                            TextFormField(
                              controller: _noteController,
                              enabled: !_isSaving,
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 1000,
                              decoration: InputDecoration(
                                labelText: 'Note (required)',
                                hintText:
                                    'Explain why the bottle state is changing',
                                counterText: '',
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD7E7F0),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD7E7F0),
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Enter a note before saving.'
                                  : null,
                            ),
                            const Text(
                              'Changes are saved immediately, even if you cancel the scan batch.',
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: saved != null
                        ? [
                            FilledButton(
                              onPressed: () => Navigator.pop(context, saved),
                              child: const Text('OK'),
                            ),
                          ]
                        : [
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF087DA9),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isSaving ? null : _save,
                              child: Text(
                                _isSaving ? 'Saving...' : 'Save condition',
                              ),
                            ),
                            if (widget.allowDamagedPickup &&
                                widget.bottle.condition == 'DAMAGED')
                              TextButton(
                                onPressed: _isSaving || _error != null
                                    ? null
                                    : () =>
                                          Navigator.pop(context, widget.bottle),
                                child: Text(widget.damagedActionLabel),
                              ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF087DA9),
                                minimumSize: const Size.fromHeight(46),
                                side: const BorderSide(
                                  color: Color(0xFF73BADD),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isSaving
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
