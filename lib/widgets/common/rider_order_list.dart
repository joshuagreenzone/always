import 'package:flutter/material.dart';

const riderOrderBlue = Color(0xFF087DA9);

class RiderOrderList extends StatelessWidget {
  final String title;
  final String summary;
  final int count;
  final bool loading;
  final String? error;
  final String emptyMessage;
  final Future<void> Function() onRefresh;
  final List<Widget> orders;

  const RiderOrderList({
    super.key,
    required this.title,
    required this.summary,
    required this.count,
    required this.loading,
    required this.error,
    required this.emptyMessage,
    required this.onRefresh,
    required this.orders,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
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
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
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
                  padding: const EdgeInsets.fromLTRB(8, 14, 12, 24),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'RIDER',
                              style: TextStyle(
                                color: Color(0xFFB8E6F5),
                                fontSize: 11,
                                letterSpacing: 1.8,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh orders',
                        onPressed: loading ? null : onRefresh,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: riderOrderBlue),
                )
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (error != null)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Color(0xFFB45309),
                                size: 32,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: riderOrderBlue,
                                ),
                                onPressed: onRefresh,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                summary,
                                style: const TextStyle(
                                  color: Color(0xFF102B40),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$count ${count == 1 ? 'order' : 'orders'}',
                              style: const TextStyle(
                                color: riderOrderBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (orders.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  color: riderOrderBlue,
                                  size: 36,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  emptyMessage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...orders.map(
                          (order) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: order,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class RiderOrderCard extends StatelessWidget {
  final int orderId;
  final String customer;
  final bool highlightCustomer;
  final IconData icon;
  final Widget badge;
  final List<Widget> details;
  final String action;
  final VoidCallback onTap;

  const RiderOrderCard({
    super.key,
    required this.orderId,
    required this.customer,
    this.highlightCustomer = false,
    required this.icon,
    required this.badge,
    required this.details,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF07344C).withValues(alpha: .05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1AA6CE), Color(0xFF08628C)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #$orderId',
                    style: const TextStyle(
                      color: Color(0xFF102B40),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer,
                    style: TextStyle(
                      color: highlightCustomer
                          ? const Color(0xFF075578)
                          : const Color(0xFF71869A),
                      fontSize: highlightCustomer ? 17 : 12,
                      fontWeight: highlightCustomer
                          ? FontWeight.w800
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(flex: 2, child: badge),
          ],
        ),
        const SizedBox(height: 14),
        ...details,
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: riderOrderBlue,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onTap,
          child: Text(
            action,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class RiderOrderDetail extends StatelessWidget {
  final String label;
  final String value;
  const RiderOrderDetail({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF71869A), fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF102B40),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class RiderOrderBadge extends StatelessWidget {
  final String label;
  final bool paid;
  const RiderOrderBadge({super.key, required this.label, this.paid = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: paid ? const Color(0xFFDCF3E7) : const Color(0xFFE3F4FA),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: paid ? const Color(0xFF087F5B) : const Color(0xFF075578),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
