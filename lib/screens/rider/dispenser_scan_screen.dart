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
  bool _loadingInventory = true;

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
    if (mounted) setState(() => _loadingInventory = true);
    try {
      final data = await _service.inventory();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingInventory = false);
    }
  }

  Future<void> _toggleCamera() async {
    if (_busy) return;
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
          if (mounted) {
            setState(() {
              _camera = false;
              _error = 'Unable to start camera.';
            });
          }
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
    if (_selected == null) {
      setState(() => _error = 'Dispenser $value is not registered.');
    }
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
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _actionLabel(String value) => switch (value) {
    'LOAD_SCAN' => 'Load for delivery',
    'DELIVERY_SCAN' => 'Deliver to customer',
    'PICKUP_SCAN' => 'Pick up from customer',
    'RETURN_SCAN' => 'Return to station',
    'MAINTENANCE' => 'Maintenance',
    _ => value.replaceAll('_', ' '),
  };

  String _stateLabel(Object? value) {
    final text = '${value ?? 'Unknown'}'.replaceAll('_', ' ').toLowerCase();
    return text.isEmpty
        ? 'Unknown'
        : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF087DA9);
    final selected = _selected;
    final counts = Map<String, dynamic>.from(_data?['counts'] as Map? ?? {});
    final customers = (_data?['customers'] as List? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F7FB),
        body: Column(
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF07344C), Color(0xFF168DB8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -35,
                    top: -65,
                    child: Container(
                      width: 210,
                      height: 210,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 12, 24),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: _busy
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _rider ? 'RIDER' : 'STATION WORKER',
                                  style: const TextStyle(
                                    color: Color(0xFFB8E6F5),
                                    fontSize: 11,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'Dispenser scans',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh dispensers',
                            onPressed: _busy || _loadingInventory
                                ? null
                                : _refresh,
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (!_busy && !_loadingInventory) await _refresh();
                },
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (_loadingInventory)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: LinearProgressIndicator(color: blue),
                      ),
                    if (_data != null) ...[
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final entry in const {
                              'READY_TO_LOAD': 'Ready to load',
                              'LOADED': 'In vehicle',
                              'DELIVERED': 'At customer',
                              'PICKED_UP': 'Collected',
                            }.entries)
                              SizedBox(
                                width: (constraints.maxWidth - 10) / 2,
                                child: _card([
                                  Text(
                                    '${counts[entry.key] ?? 0}',
                                    style: const TextStyle(
                                      color: blue,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.value,
                                    style: const TextStyle(
                                      color: Color(0xFF71869A),
                                      fontSize: 12,
                                    ),
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _card([
                      const Text(
                        'Process',
                        style: TextStyle(
                          color: Color(0xFF506C80),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _action,
                        isExpanded: true,
                        decoration: _input('Choose process'),
                        items: _actions
                            .map(
                              (action) => DropdownMenuItem(
                                value: action,
                                child: Text(_actionLabel(action)),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _action = value!;
                                _reason.clear();
                                _error = null;
                                _success = null;
                              }),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const RadialGradient(
                          colors: [Color(0xFF125574), Color(0xFF07344C)],
                          radius: .9,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF07344C)
                                .withValues(alpha: .15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _camera
                          ? SizedBox(
                              height: 260,
                              child: BottleScannerView(
                                controller: _scanner,
                                onDetect: _onDetect,
                                busy: _busy,
                                enabled: !_busy,
                              ),
                            )
                          : InkWell(
                              onTap: _busy || _data == null
                                  ? null
                                  : _toggleCamera,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 28,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: const Color(0xFF6CDCF5),
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF55D5F3)
                                                .withValues(alpha: .15),
                                            blurRadius: 24,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.qr_code_scanner,
                                        color: Color(0xFF99EAFF),
                                        size: 42,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      'Scan dispenser QR',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _actionLabel(_action),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFB8D6E5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    if (_camera)
                      Center(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _toggleCamera,
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 18,
                          ),
                          label: const Text('Stop Camera'),
                        ),
                      ),
                    if (_error != null) _feedback(_error!, error: true),
                    if (_success != null) _feedback(_success!),
                    if (_number != null) ...[
                      const SizedBox(height: 16),
                      _card([
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F4FA),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.water_drop_outlined,
                                color: blue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _number!,
                                    style: const TextStyle(
                                      color: Color(0xFF102B40),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (selected != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_stateLabel(selected['LifecycleStatus'])} · ${_stateLabel(selected['PhysicalState'])}',
                                      style: const TextStyle(
                                        color: Color(0xFF71869A),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ]),
                    ],
                    if (selected != null) ...[
                      const SizedBox(height: 14),
                      if (_jump) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5E5),
                            border: Border.all(color: const Color(0xFFF2CF91)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 20,
                                color: Color(0xFFB76A12),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'A step was skipped. Expected ${_stateLabel(_expected).toLowerCase()} before ${_actionLabel(_action).toLowerCase()}.',
                                  style: const TextStyle(
                                    color: Color(0xFF96520B),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _reason,
                          enabled: !_busy,
                          minLines: 2,
                          maxLines: 4,
                          decoration: _input('Reason for skipped scan *'),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_action != 'MAINTENANCE')
                        _card([
                          _customerField(
                            customers,
                            selected,
                            label: 'Customer',
                          ),
                        ]),
                      if (_action == 'MAINTENANCE')
                        _card([
                          const Text(
                            'Maintenance details',
                            style: TextStyle(
                              color: Color(0xFF075578),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _location,
                            isExpanded: true,
                            decoration: _input('Maintenance location'),
                            items: const [
                              DropdownMenuItem(
                                value: 'CUSTOMER',
                                child: Text('At customer'),
                              ),
                              DropdownMenuItem(
                                value: 'STATION',
                                child: Text('At station'),
                              ),
                              DropdownMenuItem(
                                value: 'OTHER',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _location = value!),
                          ),
                          if (_location == 'OTHER') ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _locationNote,
                              enabled: !_busy,
                              decoration: _input('Location details *'),
                            ),
                          ],
                          if (_location == 'CUSTOMER') ...[
                            const SizedBox(height: 16),
                            _customerField(
                              customers,
                              selected,
                              label: 'Customer *',
                            ),
                          ],
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: ValueKey(_afterMaintenance),
                            initialValue: _afterMaintenance,
                            isExpanded: true,
                            decoration: _input('Condition after maintenance'),
                            items: const [
                              DropdownMenuItem(
                                value: '',
                                child: Text('Leave unchanged'),
                              ),
                              DropdownMenuItem(
                                value: 'HEALTHY',
                                child: Text('Healthy'),
                              ),
                              DropdownMenuItem(
                                value: 'DAMAGED',
                                child: Text('Damaged'),
                              ),
                              DropdownMenuItem(
                                value: 'INOPERATIVE',
                                child: Text('Inoperative'),
                              ),
                              DropdownMenuItem(
                                value: 'MISSING',
                                child: Text('Missing'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(
                                    () => _afterMaintenance = value ?? '',
                                  ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _maintenanceNote,
                            enabled: !_busy,
                            minLines: 2,
                            maxLines: 4,
                            decoration: _input('Maintenance note *'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _work,
                            enabled: !_busy,
                            minLines: 3,
                            maxLines: 5,
                            decoration: _input('Work done *'),
                          ),
                        ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: blue,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: selected == null || _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _action == 'MAINTENANCE'
                        ? Icons.build_outlined
                        : Icons.check_circle_outline,
                    size: 20,
                  ),
            label: Text(
              _busy
                  ? 'Saving...'
                  : _action == 'MAINTENANCE'
                  ? 'Save maintenance'
                  : 'Save scan',
            ),
          ),
        ),
      ),
    );
  }

  Widget _customerField(
    List<Map<String, dynamic>> customers,
    Map<String, dynamic> selected, {
    required String label,
  }) {
    final customerId =
        _customerId ?? int.tryParse('${selected['CurrentCustomerID'] ?? ''}');
    final exists = customers.any(
      (c) => int.tryParse('${c['customerId']}') == customerId,
    );
    return DropdownButtonFormField<int>(
      key: ValueKey('customer-$_number-$_action-$_location'),
      initialValue: exists ? customerId : null,
      isExpanded: true,
      decoration: _input(label),
      items: customers
          .map(
            (c) => DropdownMenuItem(
              value: int.parse('${c['customerId']}'),
              child: Text(
                '${c['customerName']}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _busy ? null : (value) => setState(() => _customerId = value),
    );
  }

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    alignLabelWithHint: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD7E7F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD7E7F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF087DA9), width: 1.5),
    ),
  );

  Widget _feedback(String message, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF1E9) : const Color(0xFFE8F7EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: error ? const Color(0xFFB45309) : const Color(0xFF087F5B),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: error
                    ? const Color(0xFF96520B)
                    : const Color(0xFF087F5B),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
