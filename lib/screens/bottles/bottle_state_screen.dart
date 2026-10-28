import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/bottle_condition.dart';
import '../../services/bottle_condition_service.dart';
import '../../widgets/common/bottle_condition_dialog.dart';
import '../../widgets/common/bottle_scanner_view.dart';

class BottleStateScreen extends StatefulWidget {
  final Account account;
  final BottleConditionService? service;
  final Future<String?> Function(BuildContext)? scanCode;

  const BottleStateScreen({
    super.key,
    required this.account,
    this.service,
    this.scanCode,
  });

  @override
  State<BottleStateScreen> createState() => _BottleStateScreenState();
}

class _BottleStateScreenState extends State<BottleStateScreen> {
  final _number = TextEditingController();
  late final _service = widget.service ?? BottleConditionService();
  BottleCondition? _bottle;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final number = _number.text.trim();
    if (_busy) return;
    setState(() {
      _error = null;
      _bottle = null;
      _busy = number.isNotEmpty;
      if (number.isEmpty) _error = 'Enter a bottle number or scan its QR code.';
    });
    if (number.isEmpty) return;
    try {
      final bottle = await _service.getCondition(
        accId: widget.account.accId,
        bottleNumber: number,
      );
      if (!mounted) return;
      setState(() {
        _bottle = bottle;
        if (bottle == null) _error = 'Bottle not found.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final number = widget.scanCode != null
        ? await widget.scanCode!(context)
        : await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const _BottleStateScanner()),
          );
    if (!mounted || number == null || number.trim().isEmpty) return;
    _number.text = number.trim();
    await _lookup();
  }

  Future<void> _edit() async {
    final bottle = _bottle;
    if (bottle == null) return;
    final saved = await showModalBottomSheet<BottleCondition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => BottleConditionDialog(
        bottle: bottle,
        accId: widget.account.accId,
        service: _service,
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => _bottle = saved);
    // Reload available repair parts for the newly saved state.
    await _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final bottle = _bottle;
    return Scaffold(
      appBar: AppBar(title: const Text('Bottle State')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Inspect a bottle, report damage or a missing bottle, or record a repair.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _number,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Bottle number'),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _lookup,
            icon: const Icon(Icons.search),
            label: const Text('Find bottle'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan bottle QR'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (bottle != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bottle.bottleNumber,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(bottle.ownerLabel),
                    const SizedBox(height: 8),
                    Chip(label: Text(bottle.condition)),
                    if (bottle.note?.isNotEmpty == true) Text(bottle.note!),
                    if (bottle.updatedAt != null)
                      Text(
                        DateFormat.yMMMd().add_jm().format(bottle.updatedAt!),
                      ),
                    if (bottle.needsRefillAfterRecovery)
                      const Text('Refill this bottle again before delivery.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Update bottle state'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottleStateScanner extends StatefulWidget {
  const _BottleStateScanner();

  @override
  State<_BottleStateScanner> createState() => _BottleStateScannerState();
}

class _BottleStateScannerState extends State<_BottleStateScanner> {
  final _controller = createBottleScannerController();
  bool _accepted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan Bottle QR')),
    body: BottleScannerView(
      controller: _controller,
      onDetect: (capture) async {
        if (_accepted || capture.barcodes.isEmpty) return;
        final value = capture.barcodes.first.rawValue?.trim();
        if (value == null || value.isEmpty) return;
        _accepted = true;
        Navigator.pop(context, value);
      },
    ),
  );
}
