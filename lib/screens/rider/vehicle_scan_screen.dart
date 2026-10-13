import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../services/vehicle_bottle_service.dart';
import '../../services/bottle_condition_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/bottle_condition_dialog.dart';
import '../../widgets/common/bottle_scanner_view.dart';
import '../../widgets/common/rider_scan_card.dart';

class VehicleScanScreen extends StatefulWidget {
  final Account account;
  final bool returning;
  final VehicleBottleService? service;
  final BottleConditionService? conditionService;
  const VehicleScanScreen({
    super.key,
    required this.account,
    required this.returning,
    this.service,
    this.conditionService,
  });

  @override
  State<VehicleScanScreen> createState() => _VehicleScanScreenState();
}

class _VehicleScanScreenState extends State<VehicleScanScreen> {
  final _scanner = createBottleScannerController(autoStart: false);
  final List<String> _pending = [];
  late final _service = widget.service ?? VehicleBottleService();
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _returns = [];
  bool _busy = false;
  bool _camera = false;
  bool _loadingInventory = true;
  String? _error;
  String? _inventoryError;
  String? _success;
  String? _lastCameraNumber;
  DateTime? _lastCameraScan;
  String get _action => widget.returning ? 'RETURN' : 'LOAD';
  String get _title =>
      widget.returning ? 'Return to Station' : 'Load for Delivery';
  List<Map<String, dynamic>> get _current => _inventory
      .where((b) => b['status'] == (widget.returning ? 'COLLECTED' : 'LOADED'))
      .toList();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loadingInventory = true);
    try {
      final data = await _service.getInventory(widget.account.accId);
      if (!mounted) return;
      setState(() {
        _inventory = (data['bottles'] as List)
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
        _inventoryError = null;
        _returns = (data['returns'] as List)
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _inventoryError =
              'Could not refresh the bottle counts. ${_message(e)} Your scanned list is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingInventory = false);
    }
  }

  String _message(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _toggleCamera() async {
    if (_busy) return;
    setState(() => _camera = !_camera);
    try {
      if (_camera) {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && _camera) await _scanner.start();
      } else {
        await _scanner.stop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _camera = false;
          _error = 'Unable to start the camera. Check camera permissions and try again.';
        });
      }
    }
  }

  Future<void> _scan(BarcodeCapture capture) async {
    if (_busy || capture.barcodes.isEmpty) return;
    final number = capture.barcodes.first.rawValue?.trim();
    if (number == null || number.isEmpty) return;
    if (_pending.any((n) => n.toLowerCase() == number.toLowerCase())) return;
    final now = DateTime.now();
    if (_lastCameraNumber == number &&
        _lastCameraScan != null &&
        now.difference(_lastCameraScan!) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastCameraNumber = number;
    _lastCameraScan = now;
    await _addBottle(number);
  }

  Future<void> _enterNumber() async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Bottle Number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Bottle number',
            hintText: 'Example: RG-0001',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add Bottle'),
          ),
        ],
      ),
    );
    // Wait for the dialog to finish removing its text field before disposing.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (!mounted) return;
    setState(() => _busy = false);
    if (number != null && number.isNotEmpty) await _addBottle(number);
  }

  Future<void> _addBottle(String number) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_pending.length >= 200) {
        throw Exception(
          'This list has 200 bottles. Confirm it before adding more.',
        );
      }
      if (_pending.any((n) => n.toLowerCase() == number.toLowerCase())) {
        throw Exception(
          'Bottle $number is already on your scanned list. You only need to add it once.',
        );
      }
      if (!await checkBottleConditionForScan(
        context: context,
        accId: widget.account.accId,
        bottleNumber: number,
        allowDamagedPickup: widget.returning,
        damagedActionLabel: 'Return Damaged Bottle',
        requireRecoveryRefill: !widget.returning,
        service: widget.conditionService,
      )) {
        return;
      }
      if (!mounted) return;
      final bottle = await _service.verify(
        widget.account.accId,
        number,
        _action,
      );
      if (!mounted) return;
      setState(() {
        _pending.add(bottle['bottleNumber'].toString());
        _error = null;
        _success =
            'Bottle ${bottle['bottleNumber']} added. Tap ${widget.returning ? 'Confirm Return' : 'Confirm Loading'} to save it.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _success = null;
        _error = 'Bottle not added. ${_message(e)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _pending.isEmpty) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            widget.returning
                ? 'Confirm Station Return?'
                : 'Confirm Vehicle Loading?',
          ),
          content: Text(
            widget.returning
                ? 'Confirm that ${_bottles(_pending.length)} have arrived at the station. This records their return date and updates your remaining bottles.'
                : 'Confirm that ${_bottles(_pending.length)} are in your vehicle. They will be ready for you to deliver.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await _service.save(
        widget.account.accId,
        List.of(_pending),
        _action,
      );
      if (!mounted) return;
      final count = (result['count'] as num).toInt();
      final message =
          '${_bottles(count)} ${widget.returning ? 'returned to the station' : 'loaded for delivery'}. Saved successfully.';
      setState(() {
        _pending.clear();
        _error = null;
        _success = message;
      });
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _success = null;
          _error =
              'Could not confirm ${widget.returning ? 'the return' : 'loading'}. ${_message(e)} Your scanned list is kept. Refresh the counts before trying again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_pending.isNotEmpty) {
      setState(() => _busy = true);
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Scans?'),
          content: const Text('These scans have not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _busy = false);
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  String _bottles(int count) => '$count ${count == 1 ? 'bottle' : 'bottles'}';

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value.toString());
    return date == null
        ? value.toString()
        : DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  Future<void> _showInventory() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => FractionallySizedBox(
          heightFactor: .8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.returning
                            ? 'Station Return Inventory'
                            : 'Loaded Bottles',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close inventory',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_inventoryError != null)
                        _feedback(_inventoryError!, error: true),
                      _panel([
                        Text(
                          widget.returning
                              ? 'Bottles awaiting return'
                              : 'Bottles already loaded',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_current.isEmpty &&
                            !_loadingInventory &&
                            _inventoryError == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              widget.returning
                                  ? 'No picked-up bottles are waiting to be returned.'
                                  : 'No bottles are loaded yet.',
                            ),
                          ),
                        ..._current.map(
                          (b) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              widget.returning
                                  ? Icons.local_shipping_outlined
                                  : Icons.inventory_2_outlined,
                            ),
                            title: Text(b['bottleNumber'].toString()),
                            subtitle: Text(
                              b['condition'] == 'DAMAGED'
                                  ? 'Damaged - can return to station'
                                  : b['condition'] == 'MISSING'
                                  ? 'Missing - review condition before returning'
                                  : 'Healthy',
                            ),
                          ),
                        ),
                      ]),
                      if (widget.returning) ...[
                        const SizedBox(height: 12),
                        _panel([
                          Text(
                            'Recent Station Returns',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_returns.isEmpty &&
                              !_loadingInventory &&
                              _inventoryError == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Confirmed arrival counts will appear here.',
                              ),
                            ),
                          ..._returns.map(
                            (r) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.warehouse_outlined,
                                color: AppColors.success,
                              ),
                              title: Text(
                                '${_bottles((r['count'] as num).toInt())} returned',
                              ),
                              subtitle: Text(_dateLabel(r['scannedAt'])),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _pending.isEmpty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : _leave,
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!_busy) await _refresh();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel([
                Text(
                  widget.returning
                      ? 'Check bottles back into the station'
                      : 'Prepare bottles for your delivery',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.returning
                      ? '1. Pick up bottles from the customer.\n2. Scan each bottle as you unload at the station.\n3. Confirm the return to record the arrival count.'
                      : '1. Refill bottles at the station.\n2. Scan each bottle as you load your vehicle.\n3. Confirm loading before delivery.',
                ),
                const SizedBox(height: 12),
                if (_loadingInventory) const LinearProgressIndicator(),
                Text(
                  widget.returning
                      ? 'Awaiting station return: ${_current.length}'
                      : 'Loaded for delivery: ${_current.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy || _loadingInventory ? null : _showInventory,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(
                    widget.returning
                        ? 'View Return Inventory'
                        : 'View Loaded Bottles',
                  ),
                ),
                if (widget.returning)
                  const Text(
                    'Damaged bottles can be returned. Their condition stays damaged.',
                  ),
              ]),
              if (_inventoryError != null)
                _feedback(_inventoryError!, error: true),
              const SizedBox(height: 12),
              _panel([
                Text(
                  'Scan Bottles',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_camera) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 320,
                      child: BottleScannerView(
                        controller: _scanner,
                        onDetect: _scan,
                        busy: _busy,
                        enabled: _camera && !_busy,
                        message: _error ?? _success,
                        success: _error == null,
                      ),
                    ),
                  ),
                  const Text(
                    'Point the camera at one bottle QR code at a time.',
                  ),
                ],
                if (!_camera || !widget.returning)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _toggleCamera,
                    icon: Icon(
                      _camera
                          ? Icons.stop_circle_outlined
                          : Icons.qr_code_scanner,
                    ),
                    label: Text(_camera ? 'Stop Camera' : 'Start Scanning'),
                  ),
                TextButton.icon(
                  onPressed: _busy ? null : _enterNumber,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Enter Bottle Number'),
                ),
                if (_error != null) _feedback(_error!, error: true),
                if (_success != null) _feedback(_success!),
              ]),
              const SizedBox(height: 12),
              PendingBottleList(
                title: widget.returning
                    ? 'Bottles to Return'
                    : 'Bottles to Load',
                bottles: _pending,
                onRemove: _busy
                    ? null
                    : (number) => setState(() {
                        _pending.remove(number);
                        _success =
                            'Bottle $number removed from the scanned list.';
                        _error = null;
                      }),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _busy || _pending.isEmpty ? null : _save,
          icon: Icon(
            widget.returning
                ? Icons.warehouse_outlined
                : Icons.local_shipping_outlined,
          ),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _busy
                  ? 'Please wait...'
                  : '${widget.returning ? 'Confirm Return' : 'Confirm Loading'} (${_pending.length})',
            ),
          ),
        ),
      ),
    ),
  );

  Widget _panel(List<Widget> children) => RiderScanCard(children: children);

  Widget _feedback(String message, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (error ? AppColors.error : AppColors.success).withValues(
          alpha: .1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            color: error ? AppColors.error : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
