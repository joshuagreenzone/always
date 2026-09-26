import 'package:flutter/material.dart';

import '../../models/refill.dart';
import '../../services/refill_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class RefillHistoryScreen extends StatefulWidget {
  const RefillHistoryScreen({super.key});

  @override
  State<RefillHistoryScreen> createState() => _RefillHistoryScreenState();
}

class _RefillHistoryScreenState extends State<RefillHistoryScreen> {
  final RefillService _refillService = RefillService();

  List<Refill> _refills = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRefillHistory();
  }

  Future<void> _loadRefillHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final refills = await _refillService.getRefillHistory();

      if (!mounted) return;

      setState(() {
        _refills = refills;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Formats date into words (e.g., "Sep 26, 2026 at 8:42 AM")
  String _formatDate(DateTime dateTime) {
    final date = dateTime.toLocal();

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final month = months[date.month - 1];
    final day = date.day;
    final year = date.year;

    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$month $day, $year at $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'Refill History',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0284C7)),
      );
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    if (_refills.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      color: const Color(0xFF0284C7),
      onRefresh: _loadRefillHistory,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        itemCount: _refills.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final refill = _refills[index];

          return _RefillHistoryCard(
            refill: refill,
            formattedDate: _formatDate(refill.refillDateTime),
          );
        },
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.error,
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            const Text(
              'Unable to Load Refill History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.xs),

            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.lg),

            SizedBox(
              width: 180,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _loadRefillHistory,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: Colors.white,
                ),
                label: const Text(
                  'RETRY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      color: const Color(0xFF0284C7),
      onRefresh: _loadRefillHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),

          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 56,
                color: Color(0xFF0284C7),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          const Text(
            'No Refill History Yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),

          const SizedBox(height: 6),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              'Completed bottle refill records will appear here.',
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefillHistoryCard extends StatelessWidget {
  final Refill refill;
  final String formattedDate;

  const _RefillHistoryCard({required this.refill, required this.formattedDate});

  // Maps specific bottle types (Square, Round, Wilkins) to unique water styles
  _BottleStyle _getBottleStyle(String type) {
    final lower = type.toLowerCase();

    if (lower.contains('square')) {
      return const _BottleStyle(
        color: Color(0xFF0284C7), // Sky Ocean Blue
        bgColor: Color(0xFFE0F2FE),
        icon: Icons.crop_square_rounded,
      );
    } else if (lower.contains('round')) {
      return const _BottleStyle(
        color: Color(0xFF059669), // Emerald Green
        bgColor: Color(0xFFD1FAE5),
        icon: Icons.trip_origin_rounded,
      );
    } else if (lower.contains('wilkins')) {
      return const _BottleStyle(
        color: Color(0xFF0D9488), // Ocean Teal
        bgColor: Color(0xFFCCFBF1),
        icon: Icons.water_drop_rounded,
      );
    }

    // Default Fallback Style
    return const _BottleStyle(
      color: Color(0xFF2563EB), // Royal Blue
      bgColor: Color(0xFFDBEAFE),
      icon: Icons.local_drink_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _getBottleStyle(refill.bottleType);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: style.color.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: style.color.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Type Badge + Refill ID Pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // High Contrast Badge for Bottle Type
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: style.bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: style.color.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, size: 16, color: style.color),
                      const SizedBox(width: 6),
                      Text(
                        refill.bottleType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: style.color,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),

                // Refill Record ID Tag
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${refill.refillId}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Middle Section: Bottle Code with Colored Icon Marker
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: style.color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.qr_code_rounded,
                    color: style.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BOTTLE NUMBER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        refill.bottleNumber,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 10),

            // Bottom Section: Refill Timestamp
            Row(
              children: [
                const Icon(
                  Icons.access_time_filled_rounded,
                  size: 14,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formattedDate,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Helper class for mapping visual styles to bottle types
class _BottleStyle {
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _BottleStyle({
    required this.color,
    required this.bgColor,
    required this.icon,
  });
}
