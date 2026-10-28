import 'package:flutter/material.dart';

import '../../services/batch_scan_location.dart';
import '../../services/scan_lookup_service.dart';
import '../../widgets/common/unregistered_qr_dialog.dart';
import '../../models/qr_registration.dart';
import '../../widgets/common/bottle_scanner_view.dart';
import '../../widgets/common/scan_jump_dialog.dart';

import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';
import '../../models/bottle.dart';
import '../../services/refill_service.dart';
import '../../widgets/common/bottle_condition_dialog.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/rider_scan_card.dart';
import 'refilled_bottles_screen.dart';

class RefillScreen extends StatefulWidget {
  final Account account;

  const RefillScreen({super.key, required this.account});

  @override
  State<RefillScreen> createState() => _RefillScreenState();
}

class _RefillScreenState extends State<RefillScreen> {
  final RefillService _refillService = RefillService();
  final MobileScannerController _scannerController =
      createBottleScannerController();

  final _batchLocation = BatchScanLocation();
  final _lookup = ScanLookupService();
  final List<Bottle> _batch = [];
  final Set<String> _batchNumbers = {};
  final Map<String, Map<String, dynamic>> _jumpDetails = {};

  bool _isScanning = false;
  bool _isVerifying = false;
  bool _isSaving = false;
  bool _scanLocked = false;

  String? _errorMessage;
  String? _lastScannedNumber;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _startScanning() {
    if (_isSaving || _isVerifying) return;

    setState(() {
      _isScanning = true;
      _scanLocked = false;
      _errorMessage = null;
    });
  }

  Future<void> _handleQrCode(String value) async {
    final number = value.trim();

    if (!_isScanning ||
        _scanLocked ||
        _isVerifying ||
        _isSaving ||
        number.isEmpty) {
      return;
    }

    if (_batchNumbers.any((n) => n.toLowerCase() == number.toLowerCase())) {
      return;
    }
    _scanLocked = true;

    setState(() {
      _isVerifying = true;
      _lastScannedNumber = number;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<Object>([
        lookupBottleForScan(
          context,
          _lookup,
          widget.account.accId,
          number,
          'REFILL_SCAN',
        ),
        _batchLocation.get(),
      ]);
      if (!mounted) return;
      final lookup = results.first as ScanLookup;
      final ready = await checkBottleConditionForScan(
        context: context,
        accId: widget.account.accId,
        bottleNumber: number,
        initialCondition: lookup.condition,
      );
      if (!mounted) return;
      if (!ready) {
        setState(() => _errorMessage = 'Bottle not added');
        return;
      }
      final bottle = lookup.isNewUnregistered
          ? Bottle(
              bottleId: 0,
              bottleNumber: number,
              bottleTypeId: lookup.transition['bottleTypeId'] as int,
              bottleType: lookup.transition['bottleType'] as String,
              price: (lookup.transition['price'] as num).toDouble(),
              bottleRegDateTime: DateTime.now(),
            )
          : await _refillService.verifyBottle(number);

      if (!mounted) return;
      final transition = await checkScanJump(
        context: context,
        bottleNumber: bottle.bottleNumber,
        eventType: 'REFILL_SCAN',
        initialTransition: lookup.transition,
      );
      if (!mounted || transition == null) return;

      final verifiedNumber = bottle.bottleNumber.trim();

      if (_batchNumbers.contains(verifiedNumber)) {
        setState(() {
          _errorMessage = 'Bottle $verifiedNumber is already in this batch.';
        });
      } else {
        setState(() {
          _batch.add(bottle);
          _batchNumbers.add(verifiedNumber);
          _jumpDetails[verifiedNumber.toLowerCase()] = transition;
          _errorMessage = null;
        });
      }
    } on RefillException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });

        if (mounted && _isScanning) {
          setState(() {
            _scanLocked = false;
          });
        }
      }
    }
  }

  Future<void> _finishScanning() async {
    if (_batch.isEmpty || _isSaving || _isVerifying) return;

    setState(() {
      _isScanning = false;
      _errorMessage = null;
    });

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Save Refill Batch?'),
          content: Text(
            'You have verified ${_batch.length} bottle(s).\n\n'
            'Save their refill records and REFILL_SCAN audit '
            'records now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continue Scanning'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save Batch'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (confirmed != true) {
      setState(() {
        _isScanning = true;
      });
      return;
    }

    final bottleNumbers = _batch
        .map((bottle) => bottle.bottleNumber)
        .toList(growable: false);

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final position = await _batchLocation.get();

      final result = await _refillService.createRefillBatch(
        accId: widget.account.accId,
        bottleNumbers: bottleNumbers,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        jumpDetails: _jumpDetails,
      );

      if (!mounted) return;

      final savedCount = result['count'] is num
          ? (result['count'] as num).toInt()
          : bottleNumbers.length;

      setState(() {
        _batch.clear();
        _batchLocation.clear();
        _batchNumbers.clear();
        _jumpDetails.clear();
        _lastScannedNumber = null;
        _isSaving = false;
      });

      await _showSuccessDialog(
        result['message']?.toString() ??
            'Successfully saved $savedCount refill(s).',
      );
    } on RefillException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _showSuccessDialog(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Expanded(child: Text('Refill Batch Saved')),
            ],
          ),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _stopScanning() {
    if (_isVerifying || _isSaving) return;

    setState(() {
      _isScanning = false;
      _scanLocked = false;
      _errorMessage = null;
    });
  }

  void _removeBottle(Bottle bottle) {
    if (_isVerifying || _isSaving) return;

    setState(() {
      _batch.remove(bottle);
      _batchNumbers.remove(bottle.bottleNumber.trim());
      _jumpDetails.remove(bottle.bottleNumber.trim().toLowerCase());
      if (_batch.isEmpty) _batchLocation.clear();
    });
  }

  Future<void> _clearBatch() async {
    if (_isSaving || _isVerifying || _batch.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear Batch?'),
          content: const Text(
            'Remove all verified bottles from this temporary '
            'batch? No refill records have been saved yet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Bottles'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear Batch'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _batch.clear();
      _batchLocation.clear();
      _batchNumbers.clear();
      _jumpDetails.clear();
      _errorMessage = null;
      _lastScannedNumber = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF087DA9);
    final busy = _isSaving || _isVerifying;
    return PopScope(
      canPop: !busy,
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
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'STATION WORKER',
                                  style: TextStyle(
                                    color: Color(0xFFB8E6F5),
                                    fontSize: 11,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'Refill bottles',
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
                            tooltip: 'Clear batch',
                            onPressed: busy || _batch.isEmpty
                                ? null
                                : _clearBatch,
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
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
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: blue,
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: busy ? null : () {},
                          child: const Text('Refill bottles'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF07344C),
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: busy
                              ? null
                              : () {
                                  _stopScanning();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const RefilledBottlesScreen(),
                                    ),
                                  );
                                },
                          child: const Text('Ready for loading'),
                        ),
                      ),
                    ],
                  ),
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
                          color: const Color(0xFF07344C).withValues(alpha: .15),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: _isScanning
                        ? SizedBox(
                            height: 260,
                            child: BottleScannerView(
                              controller: _scannerController,
                              busy: busy,
                              enabled: _isScanning && !_isSaving,
                              message:
                                  _errorMessage ??
                                  (_lastScannedNumber == null || _isVerifying
                                      ? null
                                      : 'Scanned\n$_lastScannedNumber'),
                              success: _errorMessage == null,
                              onDetect: (capture) async {
                                if (capture.barcodes.isEmpty) return;
                                final value = capture.barcodes.first.rawValue;
                                if (value != null) await _handleQrCode(value);
                              },
                            ),
                          )
                        : InkWell(
                            onTap: busy ? null : _startScanning,
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
                                  const Text(
                                    'Scan each bottle after refilling',
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
                  if (_isScanning)
                    Center(
                      child: TextButton.icon(
                        onPressed: busy ? null : _stopScanning,
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('Stop Camera'),
                      ),
                    ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  RiderScanCard(
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'This batch',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${_batch.length} ${_batch.length == 1 ? 'bottle' : 'bottles'}',
                            style: const TextStyle(
                              color: blue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Verified bottles are saved when you confirm the batch.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_batch.isEmpty)
                    const RiderScanCard(
                      children: [
                        Text(
                          'Your scanned bottles will appear here.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ..._batch.map(
                    (bottle) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RiderScanCard(
                        color: isUnregisteredQr(bottle.bottleNumber)
                            ? Colors.orange.shade50
                            : null,
                        children: [
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
                                      bottle.bottleNumber,
                                      style: TextStyle(
                                        color:
                                            isUnregisteredQr(
                                              bottle.bottleNumber,
                                            )
                                            ? Colors.orange.shade900
                                            : null,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      bottle.bottleTypeId == 0
                                          ? 'Unregistered QR'
                                          : '${isUnregisteredQr(bottle.bottleNumber) ? 'Unregistered QR · ' : ''}${bottle.bottleType} · ₱${bottle.price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 12,
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
                                onPressed: busy
                                    ? null
                                    : () => _removeBottle(bottle),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
            onPressed: busy || _batch.isEmpty ? null : _finishScanning,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.water_drop_outlined, size: 20),
            label: Text(
              _isSaving
                  ? 'Saving refill batch...'
                  : _isVerifying
                  ? 'Verifying bottle...'
                  : 'Review and save refill',
            ),
          ),
        ),
      ),
    );
  }
}
