import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../login/login_screen.dart';

import 'assigned_orders_screen.dart';
import 'pickup_orders_screen.dart';
import 'transaction_history_screen.dart';

class RiderHomeScreen extends StatelessWidget {
  final Account account;

  const RiderHomeScreen({super.key, required this.account});

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${account.accName}',
              style: AppTextStyles.screenTitle,
            ),

            const SizedBox(height: AppSpacing.sm),

            const Text('Rider', style: AppTextStyles.bodySecondary),

            const SizedBox(height: AppSpacing.xl),

            _DashboardCard(
              icon: Icons.local_shipping,
              title: 'Assigned Orders',
              description: 'View orders assigned to you for delivery.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AssignedOrdersScreen(account: account),
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.md),

            _DashboardCard(
              icon: Icons.assignment_return,
              title: 'Pickup Bottles',
              description: 'Scan bottles returned by customers.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PickupOrdersScreen(account: account),
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.md),

            _DashboardCard(
              icon: Icons.history,
              title: 'Transaction History',
              description: 'View delivered and picked-up transactions.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TransactionHistoryScreen(accId: account.accId),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.dashboardCardPadding),
          child: Row(
            children: [
              SizedBox(
                width: AppSizes.dashboardIconSize,
                height: AppSizes.dashboardIconSize,
                child: Icon(icon, size: AppSizes.dashboardIconSize),
              ),

              const SizedBox(width: AppSpacing.md),

              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.dashboardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      description,
                      style: AppTextStyles.dashboardDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
