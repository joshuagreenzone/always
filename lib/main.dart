import 'package:flutter/material.dart';

import 'screens/login/login_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SyawlaApp());
}

class SyawlaApp extends StatelessWidget {
  const SyawlaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Syawla',

      theme: AppTheme.lightTheme,

      home: const LoginScreen(),
    );
  }
}
