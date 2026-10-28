import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../services/vehicle_bottle_service.dart';
import '../../services/scan_transition_service.dart';
import '../../services/scan_lookup_service.dart';
import '../../widgets/common/unregistered_qr_dialog.dart';
import '../../models/qr_registration.dart';
import '../../services/bottle_condition_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/bottle_condition_dialog.dart';
import '../../widgets/common/bottle_scanner_view.dart';
import '../../widgets/common/rider_scan_card.dart';
import '../../widgets/common/load_trip_history.dart';
import '../../widgets/common/scan_jump_dialog.dart';

class VehicleScanScreen extends StatefulWidget {
  final Account account;
  final bool returning;
  final VehicleBottleService? service;
  final BottleConditionService? conditionService;
  final ScanTransitionService? transitionService;
  final ScanLookupService? lookupService;
  const VehicleScanScreen({
    super.key,
    required this.account,
    required this.returning,
    this.service,
    this.conditionService,
    this.transitionService,
    this.lookupService,
  });

  @override
  State<VehicleScanScreen> createState() => _VehicleScanScreenState();
}

class _VehicleScanScreenState extends State<VehicleScanScreen> {
  final _scanner = createBottleScannerController(autoStart: false);
  final List<String> _pending = [];
  final Map<String, Map<String, dynamic>> _jumpDetails = {};
  late final _service = widget.service ?? VehicleBottleService();
  late final _lookup = widget.lookupService ?? ScanLookupService();
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _trips = [];
  int _tripsToday = 0;
  Map<String, dynamic>? _loadContext;
  final Set<String> _carried = {};
  late bool _loadReady = widget.returning;
  final String _requestKey = List.generate(
    32,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  bool _busy = false;
  bool _viewVehicle = false;
  bool _camera = false;
  bool _loadingInventory = true;
  bool _refreshing = false;
  String? _error;
  String? _inventoryError;
  String? _success;
  String? _lastCameraNumber;
  DateTime? _lastCameraScan;
  String get _action => widget.returning ? 'RETURN' : 'LOAD';
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
    if (_refreshing) return;
    _refreshing = true;
    if (mounted) setState(() => _loadingInventory = true);
    try {
      final data = await _service.getInventory(widget.account.accId);
      if (!mounted) return;
      setState(() {
        _inventory = (data['bottles'] as List)
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
        _inventoryError = null;
        _loadingInventory = false;
        _returns = (data['returns'] as List)
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
        _trips = (data['trips'] as List? ?? [])
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
        _tripsToday = (data['tripsToday'] as num? ?? 0).toInt();
      });
      if (!widget.returning && !_loadReady) {
        if (data['loadContext'] is! Map) {
          throw Exception('Update the mobile API to support load trips.');
        }
        final snapshot = Map<String, dynamic>.from(data['loadContext']);
        final previous = (snapshot['bottles'] as List)
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
        var confirmed = previous.isEmpty;
        if (previous.isNotEmpty) {
          confirmed =
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text('Undelivered bottles from previous batch'),
                  content: SingleChildScrollView(
                    child: Text(
                      'There are still ${_bottles(previous.length)} from your previous batch that have not been delivered.\n\n'
                      '${previous.map((b) => b['bottleNumber']).join('\n')}\n\nCarry these bottles into your new batch?',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm carry-over'),
                    ),
                  ],
                ),
              ) ==
              true;
        }
        if (!mounted) return;
        if (!confirmed) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
            return;
          }
          setState(
            () => _inventoryError = 'Loading cancelled. Confirm the previous bottles before starting a new batch.',
          );
          return;
        }
        setState(() {
          _loadContext = snapshot;
          _loadReady = true;
          for (final b in previous) {
            final number = b['bottleNumber'].toString();
            _pending.add(number);
            _carried.add(number.toLowerCase());
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _inventoryError =
              'Could not refresh the bottle counts. ${_message(e)} Your scanned list is unchanged.',
        );
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loadingInventory = false);
    }
  }

  String _message(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _toggleCamera() async {
    if (_busy || !_loadReady) return;
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
    if (_busy || !_loadReady) return;
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
    if (_busy || !_loadReady) return;
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
      final lookup =
          widget.conditionService == null && widget.transitionService == null
          ? await lookupBottleForScan(
              context,
              _lookup,
              widget.account.accId,
              number,
              widget.returning ? 'UNLOAD_SCAN' : 'LOAD_SCAN',
            )
          : null;
      if (!mounted) return;
      if (!await checkBottleConditionForScan(
        context: context,
        accId: widget.account.accId,
        bottleNumber: number,
        allowDamagedPickup: widget.returning,
        damagedActionLabel: 'Return Damaged Bottle',
        requireRecoveryRefill: !widget.returning,
        service: widget.conditionService,
        initialCondition: lookup?.condition,
      )) {
        return;
      }
      if (!mounted) return;
      final bottle =
          lookup?.vehicle ??
          await _service.verify(widget.account.accId, number, _action);
      if (!mounted) return;
      final transition = await checkScanJump(
        context: context,
        bottleNumber: number,
        eventType: widget.returning ? 'UNLOAD_SCAN' : 'LOAD_SCAN',
        service: widget.transitionService,
        initialTransition: lookup?.transition,
      );
      if (!mounted || transition == null) return;
      setState(() {
        _pending.add(bottle['bottleNumber'].toString());
        _jumpDetails[bottle['bottleNumber'].toString().toLowerCase()] =
            transition;
        _error = null;
        _success =
            'Bottle ${bottle['bottleNumber']} added. Tap ${widget.returning ? 'Review and save return' : 'Review and save loading'} to save it.';
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
    if (_busy || !_loadReady || _pending.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (_camera) {
        await _scanner.stop();
        if (!mounted) return;
        setState(() => _camera = false);
      }
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
        jumpDetails: _jumpDetails,
        loadContext: widget.returning ? null : _loadContext,
        requestKey: _requestKey,
      );
      if (!mounted) return;
      final count = (result['count'] as num).toInt();
      final message =
          '${_bottles(count)} ${widget.returning ? 'returned to the station' : 'loaded for delivery'}. Saved successfully.${result['batchCode'] == null ? '' : ' Trip ${result['batchCode']} (${result['carriedCount']} carried over).'}';
      setState(() {
        _pending.clear();
        _jumpDetails.clear();
        _error = null;
        _success = message;
      });
      Navigator.pop(context, message);
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

  void _showTripHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Trip history',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close trip history',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [LoadTripHistory(trips: _trips)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value.toString());
    return date == null
        ? value.toString()
        : DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _pending.isEmpty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: _loadingScreen(),
  );

  Widget _loadingScreen() => Scaffold(
    backgroundColor: const Color(0xFFF0F7FB),
    body: Column(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF07344C), Color(0xFF168DB8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 24),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _leave,
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RIDER',
                          style: TextStyle(
                            color: Color(0xFFB8E6F5),
                            fontSize: 11,
                            letterSpacing: 1.8,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          widget.returning
                              ? 'Return to station'
                              : 'Load vehicle',
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
                    onPressed: _busy ? null : _refresh,
                    tooltip: 'Refresh inventory',
                    icon: const Icon(Icons.refresh, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (!_busy) await _refresh();
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _loadTab(
                        widget.returning ? 'Return bottles' : 'Load bottles',
                        false,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _loadTab(
                        widget.returning
                            ? 'Awaiting return (${_current.length})'
                            : 'In vehicle (${_current.length})',
                        true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loadingInventory) const LinearProgressIndicator(),
                if (_inventoryError != null)
                  _feedback(_inventoryError!, error: true),
                if (!widget.returning)
                  LoadTripSummary(
                    count: _tripsToday,
                    loading: _loadingInventory,
                    onViewTrips: _showTripHistory,
                  ),
                if (_viewVehicle) ...[
                  if (_current.isEmpty &&
                      !_loadingInventory &&
                      _inventoryError == null)
                    _panel([
                      Text(
                        widget.returning
                            ? 'No bottles are awaiting return.'
                            : 'No bottles loaded yet.',
                      ),
                    ]),
                  ..._current.map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _panel([
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.water_drop_outlined,
                            color: Color(0xFF087DA9),
                          ),
                          title: Text(b['bottleNumber'].toString()),
                          subtitle: Text(
                            b['condition'] == 'DAMAGED' && widget.returning
                                ? 'Damaged - can return to station'
                                : b['condition']?.toString() ?? 'Loaded',
                          ),
                        ),
                      ]),
                    ),
                  ),
                  if (!widget.returning) ...[
                    const SizedBox(height: 14),
                    LoadTripHistory(trips: _trips),
                  ],
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
                ] else if (!_loadReady) ...[
                  const Text(
                    'Confirm previous bottles before scanning a new batch.',
                  ),
                  TextButton(
                    onPressed: _loadingInventory ? null : _refresh,
                    child: const Text('Review previous bottles'),
                  ),
                ] else ...[
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
                          color: const Color(0xFF07344C).withValues(alpha: .15),
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
                              onDetect: _scan,
                              busy: _busy,
                              enabled: _camera && !_busy,
                              message: _error ?? _success,
                              success: _error == null,
                            ),
                          )
                        : InkWell(
                            onTap: _busy ? null : _toggleCamera,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
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
                                    'Start Scanning',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    widget.returning
                                        ? 'Scan each bottle as you unload it'
                                        : 'Scan each bottle as you load it',
                                    style: TextStyle(
                                      color: Color(0xFFB8D6E5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_camera)
                        TextButton(
                          onPressed: _busy ? null : _toggleCamera,
                          child: const Text('Stop Camera'),
                        ),
                      Flexible(
                        child: TextButton.icon(
                          onPressed: _busy ? null : _enterNumber,
                          icon: const Icon(Icons.keyboard_outlined, size: 18),
                          label: const Text('Enter Bottle Number'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) _feedback(_error!, error: true),
                  if (_success != null) _feedback(_success!),
                  if (widget.returning)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Damaged bottles can be returned. Their condition stays damaged.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _panel([
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'This batch',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _bottles(_pending.length),
                          style: const TextStyle(
                            color: Color(0xFF087DA9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _pending.length / 200,
                        minHeight: 6,
                        color: const Color(0xFF087DA9),
                        backgroundColor: const Color(0xFFE2F0F7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!widget.returning)
                      Text(
                        '${_carried.length} carried over + ${_pending.length - _carried.length} newly scanned',
                      ),
                    const Text(
                      'Up to 200 bottles per batch',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (_pending.isEmpty)
                    _panel([
                      const Text(
                        'Your scanned bottles will appear here.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ]),
                  ..._pending.map(
                    (number) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _panel([
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
                                color: Color(0xFF087DA9),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    number,
                                    style: TextStyle(
                                      color: isUnregisteredQr(number)
                                          ? Colors.orange.shade900
                                          : null,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.returning
                                        ? 'Ready to return'
                                        : _carried.contains(
                                            number.toLowerCase(),
                                          )
                                        ? 'Carried over from previous batch'
                                        : 'Ready to load',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (isUnregisteredQr(number))
                                    Text(
                                      'Unregistered QR',
                                      style: TextStyle(
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFA76012),
                                backgroundColor: const Color(0xFFFFF1DB),
                              ),
                              onPressed:
                                  _busy ||
                                      _carried.contains(number.toLowerCase())
                                  ? null
                                  : () => setState(() {
                                      _pending.remove(number);
                                      _jumpDetails.remove(number.toLowerCase());
                                      _success = null;
                                      _error = null;
                                    }),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: _viewVehicle
        ? null
        : SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF087DA9),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _busy || !_loadReady || _pending.isEmpty
                  ? null
                  : _save,
              icon: Icon(
                widget.returning
                    ? Icons.warehouse_outlined
                    : Icons.local_shipping_outlined,
                size: 20,
              ),
              label: Text(
                _busy
                    ? 'Please wait...'
                    : widget.returning
                    ? 'Review and save return'
                    : 'Review and save loading',
              ),
            ),
          ),
  );

  Widget _loadTab(String label, bool inventory) {
    final selected = _viewVehicle == inventory;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF087DA9) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF07344C),
        minimumSize: const Size.fromHeight(46),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _busy
          ? null
          : () async {
              if (inventory && _camera) await _toggleCamera();
              if (mounted) setState(() => _viewVehicle = inventory);
            },
      child: Text(label),
    );
  }

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
