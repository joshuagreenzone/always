import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../widgets/common/bottle_condition_dialog.dart';
import '../../widgets/common/bottle_scanner_view.dart';

class BottleRegistrationScanScreen extends StatefulWidget {
  final Future<bool> Function(String value) onScanned;
  final Account account;
  const BottleRegistrationScanScreen({
    super.key,
    required this.onScanned,
    required this.account,
  });
  @override
  State<BottleRegistrationScanScreen> createState() =>
      _BottleRegistrationScanScreenState();
}

class _BottleRegistrationScanScreenState
    extends State<BottleRegistrationScanScreen> {
  final _controller = createBottleScannerController();
  String? _message;
  bool _success = true;
  bool _busy = false;
  final Set<String> _accepted = {};
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Bottle QR'),
      ),
      body: BottleScannerView(
        controller: _controller,
        message: _message,
        success: _success,
        busy: _busy,
        onDetect: (capture) async {
          final value = capture.barcodes.first.rawValue!.trim();
          if (_accepted.contains(value.toLowerCase())) return;
          setState(() => _busy = true);
          try {
            final ready = await checkBottleConditionForScan(
              context: context,
              accId: widget.account.accId,
              bottleNumber: value,
              allowUnregistered: true,
            );
            if (!mounted) return;
            final accepted = ready && await widget.onScanned(value);
            if (accepted) _accepted.add(value.toLowerCase());
            if (!mounted) return;
            setState(() {
              _success = accepted;
              _message = accepted
                  ? 'Scanned\n$value'
                  : 'Bottle not added\n$value';
            });
          } catch (e) {
            if (mounted)
              setState(() {
                _success = false;
                _message = e.toString().replaceFirst('Exception: ', '');
              });
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    ),
  );
}
