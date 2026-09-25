import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/login/login_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    // Safely setup animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fallback widget if controller isn't ready yet
    if (_controller == null) {
      return const Scaffold(
        backgroundColor: Colors.blue,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller!,
        builder: (context, child) {
          final progress = _controller!.value;
          // Orbital focal points for liquid gradient light shift
          final xOffset = math.sin(progress * 2 * math.pi) * 0.6;
          final yOffset = math.cos(progress * 2 * math.pi) * 0.6;

          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.heroGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                // Moving Dynamic Glow Layer 1
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(xOffset, yOffset - 0.2),
                        radius: 1.2,
                        colors: [
                          Colors.cyanAccent.withOpacity(0.35),
                          Colors.blue.shade700.withOpacity(0.15),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),

                // Moving Dynamic Glow Layer 2
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-xOffset, -yOffset + 0.2),
                        radius: 1.4,
                        colors: [
                          Colors.indigoAccent.withOpacity(0.4),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),

                // Main Screen Content
                if (child != null) child,
              ],
            ),
          );
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Logo(),

                    const SizedBox(height: AppSpacing.lg),

                    Text(
                      'ALWAYS',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.displayLarge.copyWith(
                        fontSize: 42,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 1,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.25),
                            offset: const Offset(0, 3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      'Water Ordering & Delivery',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySecondary.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSizes.screenPadding),
                        child: const LoginForm(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand mark on a colored backdrop
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const ClipOval(
        child: Image(
          image: AssetImage('assets/images/logo.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
