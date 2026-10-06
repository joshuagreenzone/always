import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/account.dart';
import '../../models/bottle.dart';
import '../../services/refill_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';

class RefillScreen extends StatefulWidget {
  final Account account;

  const RefillScreen({super.key, required this.account});

  @override
  State<RefillScreen> createState() => _RefillScreenState();
}

class _RefillScreenState extends State<RefillScreen> {
  final RefillService _refillService = RefillService();
  final MobileScannerController _scannerController = MobileScannerController();

  final List<Bottle> _batch = [];
  final Set<String> _batchNumbers = {};

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

  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Location services are turned off. '
        'Please enable GPS and try again.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is required to save the refill batch. '
        'Please enable location access in your device settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
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

    _scanLocked = true;

    if (_batchNumbers.contains(number)) {
      setState(() {
        _lastScannedNumber = number;
        _errorMessage = 'Bottle $number is already in this batch.';
      });

      await Future.delayed(const Duration(milliseconds: 1000));

      if (mounted && _isScanning) {
        setState(() {
          _errorMessage = null;
          _scanLocked = false;
        });
      }

      return;
    }

    setState(() {
      _isVerifying = true;
      _lastScannedNumber = number;
      _errorMessage = null;
    });

    try {
      final bottle = await _refillService.verifyBottle(number);

      if (!mounted) return;

      final verifiedNumber = bottle.bottleNumber.trim();

      if (_batchNumbers.contains(verifiedNumber)) {
        setState(() {
          _errorMessage = 'Bottle $verifiedNumber is already in this batch.';
        });
      } else {
        setState(() {
          _batch.add(bottle);
          _batchNumbers.add(verifiedNumber);
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

        await Future.delayed(const Duration(milliseconds: 900));

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
      final position = await _getCurrentLocation();

      final result = await _refillService.createRefillBatch(
        accId: widget.account.accId,
        bottleNumbers: bottleNumbers,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      if (!mounted) return;

      final savedCount = result['count'] is num
          ? (result['count'] as num).toInt()
          : bottleNumbers.length;

      setState(() {
        _batch.clear();
        _batchNumbers.clear();
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
      _batchNumbers.clear();
      _errorMessage = null;
      _lastScannedNumber = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'Refill Bottles',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isSaving ? _buildSavingScreen() : _buildContent(),
    );
  }

  Widget _buildSavingScreen() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF0284C7)),
          SizedBox(height: 16),
          Text(
            'Saving refill batch...',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'Please do not close the app.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SafeArea(
      child: Column(
        children: [
          if (_isScanning) _buildScanner(),

          if (_errorMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Color(0xFF0284C7),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Refill Batch',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '${_batch.length} bottle(s) verified',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                if (!_isScanning)
                  ElevatedButton.icon(
                    onPressed: _isVerifying ? null : _startScanning,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: _batch.isEmpty
                ? SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 58,
                              color: Colors.blueGrey.shade200,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No bottles scanned yet',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Start scanning to add bottles to your '
                              'temporary refill batch.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _batch.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final bottle = _batch[index];

                      return Card(
                        margin: EdgeInsets.zero,
                        color: Colors.white,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFDCFCE7),
                            child: Icon(
                              Icons.check_rounded,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                          title: Text(
                            bottle.bottleNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          subtitle: Text(
                            '${bottle.bottleType}\n'
                            '₱${bottle.price.toStringAsFixed(2)}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Remove from batch',
                            onPressed: _isVerifying || _isSaving
                                ? null
                                : () => _removeBottle(bottle),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppSizes.screenPadding),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isScanning)
                    OutlinedButton.icon(
                      onPressed: _isVerifying ? null : _stopScanning,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(
                        _isVerifying ? 'VERIFYING BOTTLE...' : 'STOP SCANNING',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
                    ),

                  if (!_isScanning && _batch.isNotEmpty)
                    TextButton.icon(
                      onPressed: _isVerifying ? null : _clearBatch,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Clear Batch'),
                    ),

                  const SizedBox(height: AppSpacing.sm),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _batch.isEmpty ||
                              _isScanning ||
                              _isVerifying ||
                              _isSaving
                          ? null
                          : _finishScanning,
                      icon: const Icon(Icons.done_all_rounded),
                      label: Text(
                        'DONE SCANNING REFILL (${_batch.length})',
                        textAlign: TextAlign.center,
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                    ),
                  ),

                  if (_isScanning)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Bottles are not saved until you finish '
                        'the batch.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return SizedBox(
      height: 220, // Reduced fixed height slightly to adapt to shorter screens
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (capture.barcodes.isEmpty) return;

              final value = capture.barcodes.first.rawValue;

              if (value != null && value.trim().isNotEmpty) {
                _handleQrCode(value);
              }
            },
          ),

          Center(
            child: Container(
              width: 200,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF38BDF8), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _isVerifying
                    ? 'Verifying $_lastScannedNumber...'
                    : 'Scan the next bottle • '
                          '${_batch.length} verified',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Keep scanning. Press Stop Scanning when finished.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
