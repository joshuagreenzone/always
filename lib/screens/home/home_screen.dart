import 'package:flutter/material.dart';

import '../../models/account.dart';
import '../rider/rider_home_screen.dart';
import '../station_worker/station_worker_home_screen.dart';

class HomeScreen extends StatelessWidget {
  final Account account;

  const HomeScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final role = account.accType.trim().toUpperCase();

    switch (role) {
      case 'STATION_WORKER':
        return StationWorkerHomeScreen(account: account);

      case 'RIDER':
        return RiderHomeScreen(account: account);

      default:
        return _UnknownRoleScreen(account: account);
    }
  }
}

class _UnknownRoleScreen extends StatelessWidget {
  final Account account;

  const _UnknownRoleScreen({required this.account});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unknown Role'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Unknown account role',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Account type: ${account.accType}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
