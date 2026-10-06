import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/bottle_type.dart';
import '../../services/bottle_service.dart';
import 'bottle_registration_scan_screen.dart';

class BottleRegistrationScreen extends StatefulWidget {
  final Account account;

  const BottleRegistrationScreen({super.key, required this.account});

  @override
  State<BottleRegistrationScreen> createState() =>
      _BottleRegistrationScreenState();
}

class _BottleRegistrationScreenState extends State<BottleRegistrationScreen> {
  final BottleService _bottleService = BottleService();

  final TextEditingController _brandController = TextEditingController();

  final TextEditingController _costController = TextEditingController();

  List<BottleType> _bottleTypes = [];

  final List<String> _scannedBottles = [];

  // QR values that failed the last registration attempt.
  //
  // These bottles remain in _scannedBottles, but are displayed
  // in red so the worker knows which bottles need attention.
  final Set<String> _errorBottles = <String>{};

  // Stores the server's error message for each problematic QR.
  final Map<String, String> _bottleErrorMessages = <String, String>{};

  BottleType? _selectedBottleType;

  String _selectedCondition = 'BRAND_NEW';

  bool _isLoadingTypes = true;
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    _loadBottleTypes();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _loadBottleTypes() async {
    try {
      final bottleTypes = await _bottleService.getBottleTypes();

      if (!mounted) return;

      setState(() {
        _bottleTypes = bottleTypes;
        _isLoadingTypes = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingTypes = false;
      });

      await _showErrorDialog(
        'Unable to Load Bottle Types',
        _cleanErrorMessage(e),
      );
    }
  }

  void _onBottleTypeChanged(BottleType? value) {
    if (value == null) return;

    setState(() {
      _selectedBottleType = value;

      // Automatically use the bottle type's configured price.
      // The worker can still manually change this value.
      _costController.text = value.price.toStringAsFixed(2);

      // A change of bottle type means the previous validation
      // errors should no longer be shown as active.
      _errorBottles.clear();
      _bottleErrorMessages.clear();
    });
  }

  Future<void> _scanBottle() async {
    if (_selectedBottleType == null) {
      await _showErrorDialog(
        'Bottle Type Required',
        'Please select a bottle type before scanning bottles.',
      );
      return;
    }

    if (_isRegistering) return;

    final String? scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BottleRegistrationScanScreen()),
    );

    if (!mounted || scannedValue == null) return;

    final bottleNumber = scannedValue.trim();

    if (bottleNumber.isEmpty) return;

    final alreadyScanned = _scannedBottles.any(
      (value) => value.toLowerCase() == bottleNumber.toLowerCase(),
    );

    if (alreadyScanned) {
      await _showErrorDialog(
        'Duplicate Scan',
        'Bottle "$bottleNumber" was already scanned '
            'in this batch.\n\n'
            'Please continue scanning another bottle or '
            'remove the duplicate from the list.',
      );
      return;
    }

    setState(() {
      _scannedBottles.add(bottleNumber);

      // New bottles start without an error state.
      _errorBottles.remove(bottleNumber);
      _bottleErrorMessages.remove(bottleNumber);
    });
  }

  void _removeBottle(int index) {
    if (_isRegistering) return;

    final bottleNumber = _scannedBottles[index];

    setState(() {
      _scannedBottles.removeAt(index);

      // Also remove its error state.
      _errorBottles.remove(bottleNumber);
      _bottleErrorMessages.remove(bottleNumber);
    });
  }

  Future<void> _clearBatch() async {
    if (_scannedBottles.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear Batch?'),
          content: const Text(
            'All scanned bottles will be removed from '
            'this batch. They will not be registered.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _scannedBottles.clear();
      _errorBottles.clear();
      _bottleErrorMessages.clear();
    });
  }

  Future<void> _confirmRegistration() async {
    if (_selectedBottleType == null) {
      await _showErrorDialog(
        'Bottle Type Required',
        'Please select a bottle type.',
      );
      return;
    }

    if (_scannedBottles.isEmpty) {
      await _showErrorDialog(
        'No Bottles Scanned',
        'Please scan at least one bottle before '
            'registering the batch.',
      );
      return;
    }

    final costText = _costController.text.trim();

    final cost = double.tryParse(costText);

    if (cost == null || cost < 0) {
      await _showErrorDialog(
        'Invalid Bottle Cost',
        'Please enter a valid bottle cost.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Registration'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are about to register '
                  '${_scannedBottles.length} bottle(s).',
                ),
                const SizedBox(height: 16),
                Text(
                  'Bottle Type',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedBottleType!.bottleType,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Condition',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedCondition == 'BRAND_NEW'
                      ? 'Brand New'
                      : 'Second Hand',
                ),
                const SizedBox(height: 12),
                Text('Cost', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(cost.toStringAsFixed(2)),
                const SizedBox(height: 16),
                Text(
                  'Scanned Bottles',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                ..._scannedBottles.map(
                  (bottle) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $bottle'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Register'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _registerBatch(cost);
  }

  Future<void> _registerBatch(double cost) async {
    if (_selectedBottleType == null || _scannedBottles.isEmpty) {
      return;
    }

    // Clear previous error highlighting before starting
    // a fresh server validation attempt.
    setState(() {
      _errorBottles.clear();
      _bottleErrorMessages.clear();
      _isRegistering = true;
    });

    try {
      final registeredBottles = await _bottleService.registerBottlesBatch(
        accId: widget.account.accId,
        bottleNumbers: List<String>.from(_scannedBottles),
        bottleTypeId: _selectedBottleType!.bottleTypeId,
        bottleBrand: _brandController.text.trim(),
        bottleCondition: _selectedCondition,
        bottleCost: cost,
      );

      if (!mounted) return;

      /*
       * IMPORTANT:
       *
       * Only clear the scanned list after the server confirms
       * that the entire database transaction committed.
       */
      setState(() {
        _scannedBottles.clear();
        _errorBottles.clear();
        _bottleErrorMessages.clear();
        _isRegistering = false;
      });

      await _showSuccessDialog(registeredBottles.length);
    } on BottleBatchRegistrationException catch (e) {
      if (!mounted) return;

      /*
       * IMPORTANT:
       *
       * The batch remains intact.
       *
       * Only the bottle identified by the server is marked
       * as problematic.
       */
      setState(() {
        _isRegistering = false;

        final bottleNumber = e.bottleNumber;

        if (bottleNumber != null && bottleNumber.trim().isNotEmpty) {
          final actualBottle = _findScannedBottle(bottleNumber);

          if (actualBottle != null) {
            _errorBottles.add(actualBottle);

            _bottleErrorMessages[actualBottle] = e.message;
          }
        }
      });

      await _showErrorDialog('Bottle Registration Failed', e.message);
    } catch (e) {
      if (!mounted) return;

      /*
       * Unknown errors also keep the scanned batch intact.
       */
      setState(() {
        _isRegistering = false;
      });

      await _showErrorDialog(
        'Batch Registration Failed',
        _cleanErrorMessage(e),
      );
    }
  }

  String? _findScannedBottle(String bottleNumber) {
    for (final scannedBottle in _scannedBottles) {
      if (scannedBottle.toLowerCase() == bottleNumber.toLowerCase()) {
        return scannedBottle;
      }
    }

    return null;
  }

  Future<void> _showSuccessDialog(int count) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Registration Successful'),
          content: Text(
            '$count bottle(s) were successfully '
            'registered.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Register Another Batch'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    setState(() {
      _brandController.clear();
      _costController.clear();
      _selectedBottleType = null;
      _selectedCondition = 'BRAND_NEW';
    });
  }

  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }

    return message;
  }

  Widget _buildBottleListItem(BuildContext context, int index) {
    final bottleNumber = _scannedBottles[index];

    final hasError = _errorBottles.contains(bottleNumber);

    final errorMessage = _bottleErrorMessages[bottleNumber];

    return Card(
      margin: EdgeInsets.zero,
      color: hasError ? Colors.red.withOpacity(0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasError ? Colors.red : Theme.of(context).dividerColor,
          width: hasError ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasError ? Colors.red : null,
          child: hasError
              ? const Icon(Icons.error_outline, color: Colors.white)
              : Text('${index + 1}'),
        ),
        title: Text(
          bottleNumber,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: hasError ? Colors.red : null,
          ),
        ),
        subtitle: hasError
            ? Text(
                errorMessage ??
                    'Registration failed. '
                        'Please remove this bottle.',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              )
            : const Text('Ready for registration'),
        trailing: IconButton(
          tooltip: 'Remove',
          onPressed: _isRegistering ? null : () => _removeBottle(index),
          icon: Icon(
            Icons.remove_circle_outline,
            color: hasError ? Colors.red : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bottle Registration'),
        actions: [
          if (_scannedBottles.isNotEmpty)
            IconButton(
              tooltip: 'Clear batch',
              onPressed: _isRegistering ? null : _clearBatch,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _isLoadingTypes
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<BottleType>(
                            value: _selectedBottleType,
                            decoration: const InputDecoration(
                              labelText: 'Bottle Type',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.local_drink_outlined),
                            ),
                            items: _bottleTypes
                                .map(
                                  (type) => DropdownMenuItem<BottleType>(
                                    value: type,
                                    child: Text(
                                      '${type.bottleType} - '
                                      '${type.price.toStringAsFixed(2)}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _isRegistering
                                ? null
                                : _onBottleTypeChanged,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _brandController,
                            enabled: !_isRegistering,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Bottle Brand',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                Icons.branding_watermark_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedCondition,
                            decoration: const InputDecoration(
                              labelText: 'Bottle Condition',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.inventory_2_outlined),
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
                            onChanged: _isRegistering
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }

                                    setState(() {
                                      _selectedCondition = value;
                                    });
                                  },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _costController,
                            enabled: !_isRegistering,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Bottle Cost',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.payments_outlined),
                            ),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _isRegistering ? null : _scanBottle,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: const Text('Scan Bottle QR'),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Text(
                                'Scanned Bottles',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Text(
                                '${_scannedBottles.length}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_scannedBottles.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.qr_code_2_rounded, size: 48),
                                  SizedBox(height: 8),
                                  Text(
                                    'No bottles scanned yet.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _scannedBottles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) =>
                                  _buildBottleListItem(context, index),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 8,
                          offset: Offset(0, -2),
                          color: Colors.black12,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isRegistering || _scannedBottles.isEmpty
                            ? null
                            : _confirmRegistration,
                        icon: _isRegistering
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _isRegistering
                              ? 'Registering...'
                              : 'Register '
                                    '${_scannedBottles.length} '
                                    'Bottle'
                                    '${_scannedBottles.length == 1 ? '' : 's'}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
