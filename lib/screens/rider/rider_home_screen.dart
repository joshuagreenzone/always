import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../../theme/app_colors.dart';
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          ),
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              onPressed: () {
                Navigator.pop(dialogContext);

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _HeroHeader(
              name: account.accName,
              onLogout: () => _showLogoutDialog(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              AppSpacing.md,
              AppSizes.screenPadding,
              AppSizes.screenPadding,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4.0,
                    bottom: AppSpacing.md,
                  ),
                  child: Text(
                    'Quick actions',
                    style: AppTextStyles.title.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                      fontSize: 18,
                    ),
                  ),
                ),

                _DashboardCard(
                  icon: Icons.local_shipping_rounded,
                  iconColor: const Color(0xFF0284C7),
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
                  icon: Icons.assignment_return_rounded,
                  iconColor: const Color(0xFFD97706),
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
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFF6366F1),
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
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatefulWidget {
  final String name;
  final VoidCallback onLogout;

  const _HeroHeader({required this.name, required this.onLogout});

  @override
  State<_HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<_HeroHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    // Wave animation loops continuously over 3 seconds
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Stack(
          children: [
            // Background Layer: Soft secondary wave effect for depth
            ClipPath(
              clipper: DynamicWaveClipper(
                animationValue: _waveController.value,
                waveFrequency: 1.2,
                waveHeight: 16.0,
                phaseOffset: 0.5,
              ),
              child: Container(
                height: 310,
                color: const Color(0xFF0284C7).withOpacity(0.35),
              ),
            ),

            // Foreground Layer: Gradient container with wave clipper
            ClipPath(
              clipper: DynamicWaveClipper(
                animationValue: _waveController.value,
                waveFrequency: 1.0,
                waveHeight: 20.0,
                phaseOffset: 0.0,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.heroGradient,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizes.screenPadding,
                      AppSpacing.sm,
                      AppSizes.screenPadding,
                      AppSpacing.xl * 2.5,
                    ),
                    child: Column(
                      children: [
                        // Logout Action Button
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            tooltip: 'Logout',
                            onPressed: widget.onLogout,
                          ),
                        ),

                        const SizedBox(height: 4),

                        // Floating Elevated Logo Avatar
                        Container(
                          width: 88,
                          height: 88,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.22),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Welcome Message
                        Text(
                          'Welcome, ${widget.name}',
                          style: AppTextStyles.headline.copyWith(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        // Rider Role Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusPill,
                            ),
                          ),
                          child: Text(
                            'Rider',
                            style: AppTextStyles.label.copyWith(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Custom Wave Clipper recalculates the path on every tick
class DynamicWaveClipper extends CustomClipper<Path> {
  final double animationValue;
  final double waveFrequency;
  final double waveHeight;
  final double phaseOffset;

  DynamicWaveClipper({
    required this.animationValue,
    this.waveFrequency = 1.0,
    this.waveHeight = 20.0,
    this.phaseOffset = 0.0,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 35);

    // Dynamic wave equation using continuous sine movement
    for (double i = 0; i <= size.width; i++) {
      double relativeX = i / size.width;
      double y =
          size.height -
          35 +
          math.sin(
                (relativeX * waveFrequency * 2 * math.pi) +
                    (animationValue * 2 * math.pi) +
                    phaseOffset,
              ) *
              waveHeight;
      path.lineTo(i, y);
    }

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant DynamicWaveClipper oldDelegate) {
    return true; // Force reclip every frame during active animation
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: iconColor.withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.12),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Highlighted Container Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),

                const SizedBox(width: AppSpacing.md),

                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.dashboardTitle.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: const Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 4),

                      Text(
                        description,
                        style: AppTextStyles.dashboardDescription.copyWith(
                          fontSize: 13,
                          height: 1.3,
                          color: const Color(0xFF64748B),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
