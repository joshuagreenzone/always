import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/batch_scan_location.dart';
import '../../services/scan_lookup_service.dart';
import '../../widgets/common/unregistered_qr_dialog.dart';
import '../../widgets/common/bottle_scanner_view.dart';
import '../../widgets/common/rider_scan_card.dart';
import '../../widgets/common/scan_jump_dialog.dart';

import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';
import '../../models/pickup_order.dart';
import '../../services/rider_service.dart';
import '../../widgets/common/bottle_condition_dialog.dart';

import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class _PendingPickupBottle {
  final String bottleNumber;
  final double latitude;
  final double longitude;
  final double accuracy;
  final String? jumpReason;
  final int? previousScanEventId;
  final int? bottleTypeId;

  _PendingPickupBottle({
    required this.bottleNumber,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.jumpReason,
    this.previousScanEventId,
    this.bottleTypeId,
  });
}

class PickupScanScreen extends StatefulWidget {
  final Account account;
  final PickupOrder? order;
  final RiderService? riderService;
  final ScanLookupService? lookupService;
  final BatchScanLocation? batchLocation;

  const PickupScanScreen({
    super.key,
    required this.account,
    this.order,
    this.riderService,
    this.lookupService,
    this.batchLocation,
  });

  @override
  State<PickupScanScreen> createState() => _PickupScanScreenState();
}

class _PickupScanScreenState extends State<PickupScanScreen> {
  final MobileScannerController _scannerController =
      createBottleScannerController(autoStart: false);
  late final RiderService _riderService = widget.riderService ?? RiderService();
  PickupOrder? _order;
  bool _viewAssigned = false;
  bool _loadingAssigned = false;
  bool _assignedLoaded = false;
  String? _assignedError;
  List<PickupOrder> _assignedOrders = [];
  bool _camera = false;
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _paymentAmountController =
      TextEditingController();
  final TextEditingController _paymentNotesController = TextEditingController();

  File? _receiptImage;
  String _paymentType = 'CASH';
  late final _batchLocation = widget.batchLocation ?? BatchScanLocation();
  late final _lookup = widget.lookupService ?? ScanLookupService();
  String? _scanMessage;
  bool _scanSuccess = true;
  bool _isProcessing = false;
  bool _loadingBalance = true;
  double? _outstandingBalance;

  late int _alreadyPickedUpCount;
  final List<_PendingPickupBottle> _scannedBottles = [];

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    if (_order != null) _loadBalance();
    _alreadyPickedUpCount = _order?.pickedUpBottleCount ?? 0;

    if (_alreadyPickedUpCount < 0) {
      _alreadyPickedUpCount = 0;
    }

    if (_order != null &&
        _alreadyPickedUpCount > _order!.deliveredBottleCount) {
      _alreadyPickedUpCount = _order!.deliveredBottleCount;
    }
  }

  @override
  void dispose() {
    _paymentAmountController.dispose();
    _paymentNotesController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignedOrders() async {
    if (_loadingAssigned) return;
    setState(() {
      _loadingAssigned = true;
      _assignedError = null;
    });
    try {
      final orders = await _riderService.getPickupOrders(widget.account.accId);
      if (!mounted) return;
      setState(() {
        _assignedOrders = orders;
        _assignedLoaded = true;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _assignedError = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAssigned = false);
    }
  }

  Widget _pickupTab(String label, bool assigned) {
    final selected = _viewAssigned == assigned;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF087DA9) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF07344C),
        minimumSize: const Size.fromHeight(46),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _isProcessing
          ? null
          : () async {
              if (assigned && _camera) await _toggleCamera();
              if (!mounted) return;
              setState(() => _viewAssigned = assigned);
              if (assigned && !_assignedLoaded) await _loadAssignedOrders();
            },
      child: Text(label, textAlign: TextAlign.center),
    );
  }

  Widget _assignedDeliveries() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loadingAssigned) const LinearProgressIndicator(),
      if (_assignedError != null)
        RiderScanCard(
          children: [
            Text(_assignedError!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: _loadAssignedOrders,
              child: const Text('Retry'),
            ),
          ],
        ),
      if (_assignedLoaded &&
          _assignedOrders.isEmpty &&
          !_loadingAssigned &&
          _assignedError == null)
        const RiderScanCard(
          children: [Text('No assigned deliveries awaiting pickup.')],
        ),
      ..._assignedOrders.map(
        (delivery) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RiderScanCard(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.assignment_return_outlined,
                  color: Color(0xFF087DA9),
                ),
                title: Text(
                  'Order #${delivery.orderId}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(delivery.customerName),
              ),
              Text(
                'Delivery #${delivery.deliveryId} · ${delivery.remainingBottleCount} left',
              ),
              const SizedBox(height: 8),
              ...delivery.bottleTypes.map(
                (type) => Text(
                  '${type.bottleType}: ${type.remainingBottleCount} to collect',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${delivery.pickedUpBottleCount} of ${delivery.deliveredBottleCount} bottles collected',
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: delivery.deliveredBottleCount <= 0
                      ? 0
                      : (delivery.pickedUpBottleCount /
                                delivery.deliveredBottleCount)
                            .clamp(0.0, 1.0),
                  minHeight: 6,
                  color: const Color(0xFF087DA9),
                  backgroundColor: const Color(0xFFE2F0F7),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed:
                    _isProcessing ||
                        (_scannedBottles.isNotEmpty &&
                            _order?.deliveryId != delivery.deliveryId)
                    ? null
                    : () {
                        setState(() {
                          if (_order?.deliveryId != delivery.deliveryId) {
                            _order = delivery;
                            _alreadyPickedUpCount =
                                delivery.pickedUpBottleCount;
                            _outstandingBalance = null;
                          }
                          _viewAssigned = false;
                        });
                        _loadBalance();
                      },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan pickup bottles'),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _orderDetailsCard(PickupOrder? order) {
    const ink = Color(0xFF07344C);
    const blue = Color(0xFF087DA9);
    const muted = Color(0xFF64748B);
    return RiderScanCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F4FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.assignment_return_outlined,
                color: blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order details',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order == null
                        ? 'Ready for pickup'
                        : 'Order #${order.orderId}',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (order != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Delivery #${order.deliveryId}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (order == null)
          const Text(
            'Scan the first bottle. Its order and customer will appear here.',
            style: TextStyle(color: muted, height: 1.5),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_outline, color: blue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CUSTOMER',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Bottles to collect',
            style: TextStyle(color: ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...order.bottleTypes.map(
            (type) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.water_drop_outlined, size: 18, color: blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      type.bottleType,
                      style: const TextStyle(color: ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${type.remainingBottleCount} to collect',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFE2EDF3)),
          ),
          const Text(
            'Pickup progress',
            style: TextStyle(color: ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '$_currentPickedUpCount of ${order.deliveredBottleCount} bottles',
            style: const TextStyle(
              color: blue,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: order.deliveredBottleCount <= 0
                  ? 0
                  : (_currentPickedUpCount / order.deliveredBottleCount).clamp(
                      0.0,
                      1.0,
                    ),
              minHeight: 7,
              color: blue,
              backgroundColor: const Color(0xFFE2F0F7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_remainingBottleCount remaining after this batch',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (_scannedBottles.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_scannedBottles.length} scanned in this batch · awaiting confirmation',
              style: const TextStyle(color: Color(0xFFA76012), fontSize: 12),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _loadBalance() async {
    final deliveryId = _order!.deliveryId;
    setState(() => _loadingBalance = true);
    double? balance;
    try {
      final order = await _riderService.getOrderDetails(
        orderId: _order!.orderId,
        accId: widget.account.accId,
      );
      final amount = order.outstandingAmount;
      if (amount != null && amount.isFinite && amount >= 0) balance = amount;
    } catch (_) {
      // Pickup remains available; confirmation checks the balance again.
    }
    if (!mounted || _order?.deliveryId != deliveryId) return;
    setState(() {
      _outstandingBalance = balance;
      _loadingBalance = false;
    });
  }

  int get _remainingBottleCount {
    if (_order == null) return 1;
    final remaining =
        _order!.deliveredBottleCount -
        _alreadyPickedUpCount -
        _scannedBottles.length;

    return remaining < 0 ? 0 : remaining;
  }

  int get _currentPickedUpCount {
    return _alreadyPickedUpCount + _scannedBottles.length;
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing ||
        _remainingBottleCount <= 0 ||
        capture.barcodes.isEmpty) {
      return;
    }

    final value = capture.barcodes.first.rawValue;

    if (value == null || value.trim().isEmpty) {
      return;
    }

    await _processBottle(value.trim());
  }

  Future<void> _processBottle(String bottleNumber) async {
    if (_isProcessing || _remainingBottleCount <= 0) return;
    if (_scannedBottles.any(
      (b) => b.bottleNumber.toLowerCase() == bottleNumber.toLowerCase(),
    )) {
      return;
    }
    setState(() {
      _isProcessing = true;
      _scanMessage = null;
    });
    try {
      final matched = await _riderService.getPickupOrderForBottle(
        widget.account.accId,
        bottleNumber,
      );
      if (!mounted) return;
      if (_order != null && matched.deliveryId != _order!.deliveryId) {
        throw Exception(
          'This bottle belongs to Order #${matched.orderId}. Confirm or clear the current batch before changing orders.',
        );
      }
      final results = await Future.wait<Object>([
        lookupBottleForScan(
          context,
          _lookup,
          widget.account.accId,
          bottleNumber,
          'PICKUP_SCAN',
        ),
        _batchLocation.get(),
      ]);
      if (!mounted) return;
      final lookup = results.first as ScanLookup;
      final ready = await checkBottleConditionForScan(
        context: context,
        accId: widget.account.accId,
        bottleNumber: bottleNumber,
        allowDamagedPickup: true,
        initialCondition: lookup.condition,
      );
      if (!mounted) return;
      if (!ready) {
        setState(() {
          _scanSuccess = false;
          _scanMessage = 'Bottle not added';
        });
        return;
      }

      final transition = await checkScanJump(
        context: context,
        bottleNumber: bottleNumber,
        eventType: 'PICKUP_SCAN',
        initialTransition: lookup.transition,
      );
      if (!mounted || transition == null) return;

      final position = await _batchLocation.get();
      if (!mounted) return;
      final firstScan = _order == null;
      setState(() {
        _order = matched;
        if (firstScan) _alreadyPickedUpCount = matched.pickedUpBottleCount;
        _scannedBottles.add(
          _PendingPickupBottle(
            bottleNumber: bottleNumber,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            jumpReason: transition['jumpReason']?.toString(),
            previousScanEventId: transition['previousScanEventId'] as int?,
            bottleTypeId: transition['bottleTypeId'] as int?,
          ),
        );
        _scanSuccess = true;
        _scanMessage = 'Scanned\n$bottleNumber';
      });
      if (firstScan) _loadBalance();
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanSuccess = false;
          _scanMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _takeReceiptPhoto(StateSetter setDialogState) async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (image == null) return;

    setDialogState(() {
      _receiptImage = File(image.path);
    });
  }

  Future<void> _completePickup() async {
    if (_scannedBottles.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);
    final confirmed = await _showPickupConfirmation();
    if (mounted) setState(() => _isProcessing = false);

    if (confirmed != true || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _scannerController.stop();
    } catch (_) {}

    try {
      final result = await _riderService.completePickup(
        accId: widget.account.accId,
        orderId: _order!.orderId,
        deliveryId: _order!.deliveryId,
        bottles: _scannedBottles
            .map(
              (item) => {
                'bottleNumber': item.bottleNumber,
                'latitude': item.latitude,
                'longitude': item.longitude,
                'accuracy': item.accuracy,
                'jumpReason': item.jumpReason,
                'previousScanEventId': item.previousScanEventId,
                'bottleTypeId': item.bottleTypeId,
              },
            )
            .toList(),
      );

      if (!mounted) return;

      final delivered = _toInt(
        result['deliveredCount'],
        fallback: _order!.deliveredBottleCount,
      );

      final pickedUp = _toInt(
        result['pickedUpCount'],
        fallback: _currentPickedUpCount,
      );

      final remaining = _toInt(
        result['remainingCount'],
        fallback: delivered - pickedUp,
      );

      final paymentStatus =
          result['paymentStatus']?.toString().toUpperCase() ?? 'UNPAID';

      final outstandingAmount = _toDouble(result['outstandingAmount']);

      _alreadyPickedUpCount = pickedUp;
      _scannedBottles.clear();
      _batchLocation.clear();

      setState(() {
        _isProcessing = false;
      });

      if (remaining > 0) {
        await _showMessage(
          'Partial Pickup Completed',
          '$pickedUp of $delivered bottles from Order #${_order!.orderId} have been picked up.\n\n'
              '$remaining bottle${remaining == 1 ? '' : 's'} remain to be picked up later.',
        );
      } else {
        await _showMessage(
          'Pickup Completed',
          'All $delivered bottles from Order #${_order!.orderId} have been picked up successfully.',
        );
      }

      if (!mounted) return;

      if ((paymentStatus == 'UNPAID' || paymentStatus == 'PARTIALLY_PAID') &&
          outstandingAmount > 0) {
        final paymentMade = await _showPaymentDialog(outstandingAmount);

        if (!mounted) return;

        if (paymentMade) {
          Navigator.pop(context, true);
          return;
        }

        await _showMessage(
          'Payment Not Collected',
          'The pickup was completed successfully.\n\n'
              'Outstanding balance: â‚±${outstandingAmount.toStringAsFixed(2)}',
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await _showMessage('Unable to Complete Pickup', message);

      if (!mounted) return;

      if (_scannedBottles.isNotEmpty) {
        await _scannerController.start();
      }
    }
  }

  Future<bool?> _showPickupConfirmation() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final count = _scannedBottles.length;
        final afterPickupCount = _currentPickedUpCount;
        final delivered = _order!.deliveredBottleCount;

        return AlertDialog(
          title: const Text('Confirm Pickup'),
          content: Text(
            'You are about to record $count bottle${count == 1 ? '' : 's'} as picked up.\n\n'
            'Pickup progress will become $afterPickupCount / $delivered.\n\n'
            'The scanned bottles will be saved to the database.\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showPaymentDialog(double outstandingAmount) async {
    _paymentAmountController.text = '0';
    _paymentNotesController.clear();
    _receiptImage = null;
    _paymentType = 'CASH';

    bool isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Collect Payment'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Outstanding Balance',
                      style: AppTextStyles.bodySecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'â‚±${outstandingAmount.toStringAsFixed(2)}',
                      style: AppTextStyles.dashboardTitle,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _paymentAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Payment Amount',
                        prefixText: 'â‚± ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentType,
                      decoration: const InputDecoration(
                        labelText: 'Payment Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(value: 'GCASH', child: Text('GCash')),
                        DropdownMenuItem(
                          value: 'BANK_TRANSFER',
                          child: Text('Bank Transfer'),
                        ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                _paymentType = value;
                                _receiptImage = null;
                              });
                            },
                    ),
                    if (_paymentType != 'CASH') ...[
                      const SizedBox(height: 16),
                      _buildReceiptSection(setDialogState, isSaving),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _paymentNotesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'You may collect the full balance or a partial payment.',
                      style: AppTextStyles.bodySecondary,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The server will reject any amount greater than the actual outstanding balance.',
                      style: AppTextStyles.bodySecondary,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final amount = double.tryParse(
                            _paymentAmountController.text.trim(),
                          );

                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid payment amount.'),
                              ),
                            );
                            return;
                          }

                          if (amount > outstandingAmount) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Payment cannot exceed â‚±${outstandingAmount.toStringAsFixed(2)}.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (_paymentType != 'CASH' && _receiptImage == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please take a picture of the payment receipt.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            await _riderService.createPayment(
                              accId: widget.account.accId,
                              orderId: _order!.orderId,
                              paymentAmount: amount,
                              paymentType: _paymentType,
                              receiptImage: _receiptImage,
                              notes: _paymentNotesController.text.trim(),
                            );

                            if (!context.mounted) return;

                            Navigator.pop(context, true);
                          } catch (e) {
                            if (!context.mounted) return;

                            String message = e.toString();
                            if (message.startsWith('Exception: ')) {
                              message = message.substring('Exception: '.length);
                            }

                            setDialogState(() {
                              isSaving = false;
                            });

                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(message)));
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Receive Payment'),
                ),
              ],
            );
          },
        );
      },
    );

    return result == true;
  }

  Widget _buildReceiptSection(StateSetter setDialogState, bool isSaving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payment Receipt', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Take a picture of the payment receipt or transaction confirmation.',
          style: AppTextStyles.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_receiptImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            child: Image.file(
              _receiptImage!,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
            ),
          ),
        if (_receiptImage != null) const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isSaving
                ? null
                : () async {
                    await _takeReceiptPhoto(setDialogState);
                  },
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(
              _receiptImage == null
                  ? 'Take Receipt Photo'
                  : 'Retake Receipt Photo',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleBack() async {
    if (_scannedBottles.isEmpty) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    setState(() => _isProcessing = true);
    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text('Discard Scanned Bottles?'),
          content: Text(
            '${_scannedBottles.length} bottle${_scannedBottles.length == 1 ? '' : 's'} have been scanned but not saved.\n\n'
            'If you leave this screen, these scans will be discarded.\n\n'
            'No database transaction has been created for these scans.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );

    if (mounted) setState(() => _isProcessing = false);
    if (discard == true && mounted) {
      _scannedBottles.clear();
      _batchLocation.clear();
      Navigator.pop(context);
    }
  }

  Future<void> _showMessage(String title, String message) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  int _toInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    return int.tryParse(value.toString()) ?? fallback;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    return double.tryParse(value.toString()) ?? 0;
  }

  Future<void> _toggleCamera() async {
    if (_isProcessing) return;
    setState(() => _camera = !_camera);
    try {
      if (_camera) {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && _camera) await _scannerController.start();
      } else {
        await _scannerController.stop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _camera = false;
          _scanSuccess = false;
          _scanMessage =
              'Unable to start camera. Check permissions and try again.';
        });
      }
    }
  }

  Future<void> _enterNumber() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final controller = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Bottle Number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Bottle number'),
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
    await Future<void>.delayed(const Duration(milliseconds: 200));
    controller.dispose();
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (number != null && number.isNotEmpty) await _processBottle(number);
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF087DA9);
    final order = _order;
    final busy = _isProcessing;
    return PopScope(
      canPop: !busy && _scannedBottles.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !busy) await _handleBack();
      },
      child: Scaffold(
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
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 20, 24),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: busy ? null : _handleBack,
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
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
                              'Pickup bottles',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _pickupTab('Pickup bottles', false)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _pickupTab(
                            _assignedLoaded
                                ? 'Assigned deliveries (${_assignedOrders.length})'
                                : 'Assigned deliveries',
                            true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_viewAssigned) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _loadingAssigned
                              ? null
                              : _loadAssignedOrders,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh deliveries'),
                        ),
                      ),
                      _assignedDeliveries(),
                    ] else ...[
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: const RadialGradient(
                            colors: [Color(0xFF125574), Color(0xFF07344C)],
                            radius: .9,
                          ),
                        ),
                        child: _camera
                            ? SizedBox(
                                height: 260,
                                child: BottleScannerView(
                                  controller: _scannerController,
                                  onDetect: _handleScan,
                                  enabled: !busy && _remainingBottleCount > 0,
                                  busy: busy,
                                  message: _scanMessage,
                                  success: _scanSuccess,
                                ),
                              )
                            : InkWell(
                                onTap: busy ? null : _toggleCamera,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 28,
                                    horizontal: 16,
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.qr_code_scanner,
                                        color: Color(0xFF99EAFF),
                                        size: 64,
                                      ),
                                      SizedBox(height: 18),
                                      Text(
                                        'Start Scanning',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      SizedBox(height: 5),
                                      Text(
                                        'Scan a bottle to find its pickup order',
                                        textAlign: TextAlign.center,
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          if (_camera)
                            TextButton(
                              onPressed: busy ? null : _toggleCamera,
                              child: const Text('Stop Camera'),
                            ),
                          TextButton.icon(
                            onPressed: busy ? null : _enterNumber,
                            icon: const Icon(Icons.keyboard_outlined, size: 18),
                            label: const Text('Enter Bottle Number'),
                          ),
                        ],
                      ),
                      if (_scanMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _scanMessage!,
                            style: TextStyle(
                              color: _scanSuccess ? blue : Colors.red,
                            ),
                          ),
                        ),
                      _orderDetailsCard(order),
                      if (order != null) ...[
                        const SizedBox(height: 12),
                        RiderScanCard(
                          children: [
                            Text(
                              _loadingBalance
                                  ? 'Checking balance...'
                                  : _outstandingBalance == null
                                  ? 'Balance unavailable'
                                  : _outstandingBalance! > 0
                                  ? '₱${_outstandingBalance!.toStringAsFixed(2)} outstanding'
                                  : 'No outstanding balance',
                            ),
                            const Text(
                              'Payment is checked again after pickup.',
                            ),
                            if (!_loadingBalance && _outstandingBalance == null)
                              TextButton(
                                onPressed: busy ? null : _loadBalance,
                                child: const Text('Retry balance'),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      PendingBottleList(
                        title: 'This batch',
                        bottles: _scannedBottles
                            .map((b) => b.bottleNumber)
                            .toList(),
                        onRemove: busy
                            ? null
                            : (number) => setState(() {
                                _scannedBottles.removeWhere(
                                  (b) => b.bottleNumber == number,
                                );
                                if (_scannedBottles.isEmpty &&
                                    widget.order == null) {
                                  _order = null;
                                  _alreadyPickedUpCount = 0;
                                  _batchLocation.clear();
                                }
                              }),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _viewAssigned
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: blue,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _scannedBottles.isNotEmpty && !busy
                      ? _completePickup
                      : null,
                  child: Text(busy ? 'Please wait...' : 'Confirm pickup'),
                ),
              ),
      ),
    );
  }
}
