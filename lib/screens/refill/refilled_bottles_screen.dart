import 'package:flutter/material.dart';

import '../../models/refill.dart';
import '../../services/refill_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

class RefilledBottlesScreen extends StatefulWidget {
  const RefilledBottlesScreen({super.key});

  @override
  State<RefilledBottlesScreen> createState() => _RefilledBottlesScreenState();
}

class _RefilledBottlesScreenState extends State<RefilledBottlesScreen> {
  final RefillService _refillService = RefillService();

  List<Refill> _refills = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRefills();
  }

  Future<void> _loadRefills() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final refills = await _refillService.getRefills();

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

  String _formatDate(DateTime dateTime) {
    final date = dateTime.toLocal();

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year;

    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;

    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$month/$day/$year $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Refilled Bottles')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    if (_refills.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh: _loadRefills,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        itemCount: _refills.length,
        itemBuilder: (context, index) {
          final refill = _refills[index];

          return _RefillCard(
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
            const Icon(
              Icons.error_outline,
              size: AppSizes.largeIconSize,
              color: AppColors.error,
            ),

            const SizedBox(height: AppSpacing.md),

            const Text(
              'Unable to Load Refills',
              style: AppTextStyles.sectionTitle,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.sm),

            Text(
              _errorMessage!,
              style: AppTextStyles.bodySecondary,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.lg),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loadRefills,
                child: const Text('RETRY'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: _loadRefills,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 160),

          const Icon(
            Icons.water_drop_outlined,
            size: AppSizes.largeIconSize,
            color: AppColors.textSecondary,
          ),

          const SizedBox(height: AppSpacing.md),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'No bottles have been refilled yet.',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefillCard extends StatelessWidget {
  final Refill refill;
  final String formattedDate;

  const _RefillCard({required this.refill, required this.formattedDate});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
        child: Row(
          children: [
            const CircleAvatar(radius: 24, child: Icon(Icons.water_drop)),

            const SizedBox(width: AppSpacing.md),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    refill.bottleNumber,
                    style: AppTextStyles.dashboardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: AppSpacing.xs),

                  Text(
                    refill.bottleType,
                    style: AppTextStyles.bodySecondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: AppSpacing.xs),

                  Text(
                    'Refilled: $formattedDate',
                    style: AppTextStyles.dashboardDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: AppSpacing.sm),

            const Icon(Icons.check_circle, size: 26, color: AppColors.success),
          ],
        ),
      ),
    );
  }
}
