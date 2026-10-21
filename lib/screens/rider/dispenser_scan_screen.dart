import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';
import '../../services/dispenser_service.dart';
import '../../widgets/common/bottle_scanner_view.dart';

class DispenserScanScreen extends StatefulWidget {
  final Account account;
  final DispenserService? service;

  const DispenserScanScreen({super.key, required this.account, this.service});

  @override
  State<DispenserScanScreen> createState() => _DispenserScanScreenState();
}

class _DispenserScanScreenState extends State<DispenserScanScreen> {
  final _scanner = createBottleScannerController(autoStart: false);
  final _reason = TextEditingController();
  final _maintenanceNote = TextEditingController();
  final _locationNote = TextEditingController();
  final _work = TextEditingController();
  late final _service = widget.service ?? DispenserService();
  Map<String, dynamic>? _data;
  String? _number;
  String? _error;
  String? _success;
  String _action = 'LOAD_SCAN';
  String _location = 'STATION';
  String _afterMaintenance = '';
  int? _customerId;
  bool _camera = false;
  bool _busy = false;

  bool get _rider => widget.account.hasRole('RIDER');
  List<String> get _actions => [
    if (_rider) ...['LOAD_SCAN', 'DELIVERY_SCAN', 'PICKUP_SCAN'],
    'RETURN_SCAN',
    'MAINTENANCE',
  ];
  Map<String, dynamic>? get _selected {
    if (_number == null || _data == null) return null;
    for (final row in (_data!['dispensers'] as List)) {
      final item = Map<String, dynamic>.from(row as Map);
      if (item['DispenserNumber'] == _number) return item;
    }
    return null;
  }

  String get _expected => switch (_action) {
    'LOAD_SCAN' => 'AVAILABLE',
    'DELIVERY_SCAN' => 'LOADED',
    'PICKUP_SCAN' => 'DELIVERED',
    'RETURN_SCAN' => 'PICKED_UP',
    _ => '',
  };
  bool get _jump =>
      _selected != null &&
      _action != 'MAINTENANCE' &&
      _selected!['LifecycleStatus'] != _expected;

  @override
  void initState() {
    super.initState();
    _action = _actions.first;
    _refresh();
  }

  @override
  void dispose() {
    _scanner.dispose();
    _reason.dispose();
    _maintenanceNote.dispose();
    _locationNote.dispose();
    _work.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final data = await _service.inventory();
      if (mounted)
        setState(() {
          _data = data;
          _error = null;
        });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    }
  }

  Future<void> _toggleCamera() async {
    if (_camera) {
      await _scanner.stop();
      if (mounted) setState(() => _camera = false);
    } else {
      setState(() {
        _camera = true;
        _number = null;
        _error = null;
        _success = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        try {
          await _scanner.start();
        } catch (_) {
          if (mounted)
            setState(() {
              _camera = false;
              _error = 'Unable to start camera.';
            });
        }
      }
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final value = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue?.trim().toUpperCase();
    if (value == null || value.isEmpty || _busy) return;
    await _scanner.stop();
    if (!mounted) return;
    setState(() {
      _camera = false;
      _number = value;
      _customerId = null;
      _reason.clear();
      _error = null;
      _success = null;
    });
    if (_selected == null)
      setState(() => _error = 'Dispenser $value is not registered.');
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _busy) return;
    if (_jump && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Explain why the expected scan was skipped.');
      return;
    }
    final customer =
        _customerId ?? int.tryParse('${selected['CurrentCustomerID'] ?? ''}');
    final maintenanceCustomer =
        _customerId ?? int.tryParse('${selected['CurrentCustomerID'] ?? ''}');
    if ((_action == 'DELIVERY_SCAN' || _action == 'PICKUP_SCAN') &&
        customer == null) {
      setState(() => _error = 'Select a customer.');
      return;
    }
    if (_action == 'MAINTENANCE' && _work.text.trim().isEmpty) {
      setState(() => _error = 'Describe the maintenance work.');
      return;
    }
    if (_action == 'MAINTENANCE' && _maintenanceNote.text.trim().isEmpty) {
      setState(() => _error = 'Enter a maintenance note.');
      return;
    }
    if (_action == 'MAINTENANCE' &&
        _location == 'CUSTOMER' &&
        maintenanceCustomer == null) {
      setState(
        () => _error = 'Select the customer where maintenance was done.',
      );
      return;
    }
    if (_action == 'MAINTENANCE' &&
        _location == 'OTHER' &&
        _locationNote.text.trim().isEmpty) {
      setState(() => _error = 'Enter the maintenance location details.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_action == 'MAINTENANCE') {
        await _service.maintenance(
          accId: widget.account.accId,
          dispenserNumber: _number!,
          maintenanceNote: _maintenanceNote.text.trim(),
          workDone: _work.text.trim(),
          locationType: _location,
          locationNote: _location == 'OTHER' ? _locationNote.text.trim() : null,
          customerId: _location == 'CUSTOMER' ? maintenanceCustomer : null,
          newPhysicalState: _afterMaintenance.isEmpty
              ? null
              : _afterMaintenance,
        );
      } else {
        await _service.scan(
          accId: widget.account.accId,
          dispenserNumber: _number!,
          eventType: _action,
          customerId: customer,
          jumpReason: _jump ? _reason.text.trim() : null,
        );
      }
      if (!mounted) return;
      setState(() {
        _success = '${_action.replaceAll('_', ' ')} saved for $_number.';
        _number = null;
        _reason.clear();
        _maintenanceNote.clear();
        _locationNote.clear();
        _work.clear();
        _customerId = null;
        _afterMaintenance = '';
      });
      await _refresh();
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final customers = (_data?['customers'] as List? ?? [])
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();
    final counts = Map<String, dynamic>.from(_data?['counts'] as Map? ?? {});
    return Scaffold(
      appBar: AppBar(title: const Text('Dispenser scans')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_data == null) const LinearProgressIndicator(),
          if (_data != null)
            Wrap(
              spacing: 8,
              children: ['READY_TO_LOAD', 'LOADED', 'DELIVERED', 'PICKED_UP']
                  .map(
                    (key) => Chip(
                      label: Text(
                        '${key.replaceAll('_', ' ')}: ${counts[key] ?? 0}',
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _action,
            decoration: const InputDecoration(labelText: 'Process'),
            items: _actions
                .map(
                  (a) => DropdownMenuItem(
                    value: a,
                    child: Text(a.replaceAll('_', ' ')),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _action = value!;
                    _reason.clear();
                  }),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _toggleCamera,
            icon: Icon(_camera ? Icons.close : Icons.qr_code_scanner),
            label: Text(_camera ? 'Close scanner' : 'Scan dispenser QR'),
          ),
          if (_camera)
            SizedBox(
              height: 280,
              child: BottleScannerView(
                controller: _scanner,
                onDetect: _onDetect,
                busy: _busy,
              ),
            ),
          if (_number != null) ...[
            const SizedBox(height: 16),
            Text(
              'Scanned: $_number',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (selected != null)
              Text(
                'Current process: ${selected['LifecycleStatus']} | State: ${selected['PhysicalState']}',
              ),
          ],
          if (selected != null) ...[
            if (_jump) ...[
              const SizedBox(height: 12),
              Text(
                'Expected $_expected before ${_action.replaceAll('_', ' ')}. This scan will skip a step.',
                style: const TextStyle(color: Colors.deepOrange),
              ),
              TextField(
                controller: _reason,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for skipped scan *',
                ),
              ),
            ],
            if (_action != 'MAINTENANCE') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue:
                    _customerId ??
                    int.tryParse('${selected['CurrentCustomerID'] ?? ''}'),
                decoration: const InputDecoration(labelText: 'Customer'),
                key: ValueKey('customer-$_number-$_action'),
                items: customers
                    .map(
                      (c) => DropdownMenuItem(
                        value: int.parse('${c['customerId']}'),
                        child: Text('${c['customerName']}'),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _customerId = value),
              ),
            ],
            if (_action == 'MAINTENANCE') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _location,
                decoration: const InputDecoration(
                  labelText: 'Maintenance location',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'CUSTOMER',
                    child: Text('At customer'),
                  ),
                  DropdownMenuItem(value: 'STATION', child: Text('At station')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                ],
                onChanged: (value) => setState(() => _location = value!),
              ),
              if (_location == 'OTHER')
                TextField(
                  controller: _locationNote,
                  decoration: const InputDecoration(
                    labelText: 'Location details *',
                  ),
                ),
              if (_location == 'CUSTOMER')
                DropdownButtonFormField<int>(
                  initialValue:
                      _customerId ??
                      int.tryParse('${selected['CurrentCustomerID'] ?? ''}'),
                  decoration: const InputDecoration(
                    labelText: 'Customer where maintenance was done *',
                  ),
                  items: customers
                      .map(
                        (c) => DropdownMenuItem(
                          value: int.parse('${c['customerId']}'),
                          child: Text('${c['customerName']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _customerId = value),
                ),
              DropdownButtonFormField<String>(
                key: ValueKey(_afterMaintenance),
                initialValue: _afterMaintenance,
                decoration: const InputDecoration(
                  labelText: 'State after maintenance (optional)',
                ),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Leave unchanged')),
                  DropdownMenuItem(value: 'HEALTHY', child: Text('Healthy')),
                  DropdownMenuItem(value: 'DAMAGED', child: Text('Damaged')),
                  DropdownMenuItem(
                    value: 'INOPERATIVE',
                    child: Text('Inoperative'),
                  ),
                  DropdownMenuItem(value: 'MISSING', child: Text('Missing')),
                ],
                onChanged: (value) =>
                    setState(() => _afterMaintenance = value ?? ''),
              ),
              TextField(
                controller: _maintenanceNote,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Maintenance note *',
                ),
              ),
              TextField(
                controller: _work,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Work done *'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save scan'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_success != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _success!,
                style: const TextStyle(color: Colors.green),
              ),
            ),
        ],
      ),
    );
  }
}
