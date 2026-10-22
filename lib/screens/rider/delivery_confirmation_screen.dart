import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../models/order_details.dart';

import '../../theme/app_sizes.dart';

import '../../services/rider_service.dart';

import 'payment_screen.dart';

class DeliveryConfirmationScreen extends StatefulWidget {
  final Account account;
  final OrderDetails order;

  /*
   * Temporarily scanned bottles.
   *
   * Each item contains:
   * bottleNumber
   * latitude
   * longitude
   * accuracy
   *
   * These bottles have not yet been saved to the database.
   */
  final List<Map<String, dynamic>> scannedBottles;

  const DeliveryConfirmationScreen({
    super.key,
    required this.account,
    required this.order,
    required this.scannedBottles,
  });

  @override
  State<DeliveryConfirmationScreen> createState() =>
      _DeliveryConfirmationScreenState();
}

class _DeliveryConfirmationScreenState
    extends State<DeliveryConfirmationScreen> {
  final TextEditingController _incompleteReasonController =
      TextEditingController();

  bool _isSubmitting = false;

  bool get _isPartialDelivery =>
      widget.scannedBottles.length < widget.order.totalQuantity;

  @override
  void dispose() {
    _incompleteReasonController.dispose();
    super.dispose();
  }

  // ============================================================
  // DIALOG
  // ============================================================

  Future<void> _showMessage({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CONFIRM DELIVERY
  // ============================================================

  Future<void> _handleConfirmDelivery() async {
    if (_isSubmitting) return;

    final int scannedCount = widget.scannedBottles.length;
    final int orderedCount = widget.order.totalQuantity;

    if (scannedCount < 1) {
      await _showMessage(
        title: 'No Bottles Scanned',
        message: 'Scan at least one bottle before confirming delivery.',
      );
      return;
    }

    if (scannedCount > orderedCount) {
      await _showMessage(
        title: 'Invalid Bottle Count',
        message: 'The scanned bottle count exceeds the ordered quantity.',
      );
      return;
    }

    final String incompleteReason = _incompleteReasonController.text.trim();

    if (_isPartialDelivery && incompleteReason.isEmpty) {
      await _showMessage(
        title: 'Reason Required',
        message:
            'Please explain why the delivery is incomplete before continuing.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final riderService = RiderService();

      // Save the delivery first. The API must support incompleteReason
      // and mark the delivery INCOMPLETE when fewer bottles are delivered.
      await riderService.completeDelivery(
        accId: widget.account.accId,
        orderId: widget.order.orderId,
        deliveryId: widget.order.deliveryId,
        bottles: widget.scannedBottles,
        incompleteReason: _isPartialDelivery ? incompleteReason : null,
      );

      if (!mounted) return;

      await _showMessage(
        title: _isPartialDelivery
            ? 'Partial Delivery Saved'
            : 'Delivery Completed',
        message: _isPartialDelivery
            ? 'Order #${widget.order.orderId}: $scannedCount of $orderedCount '
                  'bottles delivered. The incomplete delivery was recorded successfully.'
            : 'Order #${widget.order.orderId} was delivered successfully.',
      );

      if (!mounted) return;

      /*
       * The delivery is now recorded. Do not complete it a second time
       * from PaymentScreen.
       *
       * If payment remains outstanding, open the payment screen.
       * Otherwise, return to the rider's first screen.
       */
      if (widget.order.paymentStatus == 'PAID') {
        Navigator.popUntil(context, (route) => route.isFirst);
        return;
      }

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            account: widget.account,
            order: widget.order,
            scannedBottles: widget.scannedBottles,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String message = e.toString();

      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      await _showMessage(title: 'Delivery Failed', message: message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF087DA9);
    final scanned = widget.scannedBottles.length;
    final ordered = widget.order.totalQuantity;
    final progress = ordered > 0 ? (scanned / ordered).clamp(0.0, 1.0) : 0.0;
    return PopScope(
      canPop: !_isSubmitting,
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
                      padding: const EdgeInsets.fromLTRB(8, 14, 20, 26),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back to scanning',
                            onPressed: _isSubmitting
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
                                  'Order #${widget.order.orderId}',
                                  style: const TextStyle(
                                    color: Color(0xFFB8E6F5),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'Confirm delivery',
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
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Delivered',
                                  style: TextStyle(
                                    color: Color(0xFF102B40),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  '$scanned of $ordered bottles',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Color(0xFF102B40),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              color: blue,
                              backgroundColor: const Color(0xFFE2F0F7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isPartialDelivery) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5E5),
                          border: Border.all(color: const Color(0xFFF2CF91)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFB76A12),
                              size: 20,
                            ),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Partial delivery needs an explanation',
                                style: TextStyle(
                                  color: Color(0xFF96520B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Reason',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _incompleteReasonController,
                        enabled: !_isSubmitting,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Explain why the remaining bottles could not be delivered...',
                          hintStyle: const TextStyle(
                            color: Color(0xFF8A9BAC),
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFD7E7F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFD7E7F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: blue,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: blue.withValues(alpha: .2),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: blue,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isSubmitting
                            ? null
                            : _handleConfirmDelivery,
                        child: _isSubmitting
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Saving delivery...'),
                                ],
                              )
                            : const Text(
                                'Submit delivery',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: blue),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text(
                        'Back to scanning',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
