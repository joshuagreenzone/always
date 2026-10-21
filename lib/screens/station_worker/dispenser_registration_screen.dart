import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../services/dispenser_service.dart';
import '../../widgets/common/bottle_scanner_view.dart';

class DispenserRegistrationScreen extends StatefulWidget {
  final Account account;
  final DispenserService? service;
  final Future<String?> Function(BuildContext)? scanCode;

  const DispenserRegistrationScreen({
    super.key,
    required this.account,
    this.service,
    this.scanCode,
  });

  @override
  State<DispenserRegistrationScreen> createState() =>
      _DispenserRegistrationScreenState();
}

class _DispenserRegistrationScreenState
    extends State<DispenserRegistrationScreen> {
  final _form = GlobalKey<FormState>();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _cost = TextEditingController(text: '0.00');
  late final _service = widget.service ?? DispenserService();
  String? _number;
  String? _error;
  String _acquisition = 'BRAND_NEW';
  String _payment = 'FREE';
  bool _busy = false;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final value = widget.scanCode != null
        ? await widget.scanCode!(context)
        : await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const _DispenserQrScreen()),
          );
    if (!mounted || value == null || value.trim().isEmpty) return;
    final number = value.trim().toUpperCase();
    setState(() {
      if (RegExp(r'^[A-Z0-9][A-Z0-9-]{2,63}$').hasMatch(number)) {
        _number = number;
        _error = null;
      } else {
        _error =
            'Use a dispenser QR containing 3 to 64 letters, numbers or dashes.';
      }
    });
  }

  Future<void> _register() async {
    if (_busy || _number == null || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.register(
        accId: widget.account.accId,
        dispenserNumber: _number!,
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        dispenserAcquisition: _acquisition,
        dispenserPaymentStatus: _payment,
        dispenserCost: _payment == 'FREE' ? 0 : double.parse(_cost.text.trim()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dispenser $_number registered successfully.')),
      );
      setState(() {
        _number = null;
        _brand.clear();
        _model.clear();
        _cost.text = '0.00';
        _acquisition = 'BRAND_NEW';
        _payment = 'FREE';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Dispenser Registration')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Scan the dispenser QR code, then enter its details to register it.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(
                  _number == null
                      ? 'Scan Dispenser QR'
                      : 'Scan a Different Dispenser',
                ),
              ),
              if (_number != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(_number!),
                  subtitle: const Text('Scanned dispenser'),
                ),
                TextFormField(
                  controller: _brand,
                  enabled: !_busy,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Brand',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _model,
                  enabled: !_busy,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('acquisition-$_acquisition'),
                  initialValue: _acquisition,
                  decoration: const InputDecoration(
                    labelText: 'Acquisition Condition',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'BRAND_NEW',
                      child: Text('Brand New'),
                    ),
                    DropdownMenuItem(
                      value: 'SECOND_HAND',
                      child: Text('Second Hand'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _acquisition = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('payment-$_payment'),
                  initialValue: _payment,
                  decoration: const InputDecoration(
                    labelText: 'Payment Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'FREE', child: Text('Free')),
                    DropdownMenuItem(value: 'PAID', child: Text('Paid')),
                    DropdownMenuItem(value: 'UNPAID', child: Text('Unpaid')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _payment = value!;
                          if (_payment == 'FREE') _cost.text = '0.00';
                        }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cost,
                  enabled: !_busy && _payment != 'FREE',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Acquisition Cost',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_payment == 'FREE') return null;
                    final cost = double.tryParse(value?.trim() ?? '');
                    if (cost == null ||
                        !cost.isFinite ||
                        cost < 0.01 ||
                        cost > 9999999999.99) {
                      return 'Enter a cost from 0.01 to 9,999,999,999.99.';
                    }
                    return null;
                  },
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy || _number == null ? null : _register,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_busy ? 'Registering...' : 'Register Dispenser'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DispenserQrScreen extends StatefulWidget {
  const _DispenserQrScreen();

  @override
  State<_DispenserQrScreen> createState() => _DispenserQrScreenState();
}

class _DispenserQrScreenState extends State<_DispenserQrScreen> {
  final _scanner = createBottleScannerController();
  bool _accepted = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Scan Dispenser QR'),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: BottleScannerView(
      controller: _scanner,
      onDetect: (capture) async {
        if (_accepted) return;
        final value = capture.barcodes.first.rawValue?.trim();
        if (value == null || value.isEmpty) return;
        _accepted = true;
        Navigator.pop(context, value);
      },
    ),
  );
}
