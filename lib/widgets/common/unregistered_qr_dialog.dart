import 'package:flutter/material.dart';

import '../../models/bottle_type.dart';
import '../../services/bottle_service.dart';
import '../../services/scan_lookup_service.dart';

Future<ScanLookup> lookupBottleForScan(
  BuildContext context,
  ScanLookupService service,
  int accId,
  String number,
  String eventType, {
  BottleService? bottleService,
}) async {
  final lookup = await service.get(accId, number, eventType);
  if (!lookup.isNewUnregistered) return lookup;
  final types = await (bottleService ?? BottleService()).getBottleTypes();
  if (!context.mounted) throw Exception('Scan cancelled.');
  final type = await showDialog<BottleType>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Choose bottle type'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text('Unregistered QR: $number'),
        ),
        ...types.map(
          (type) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, type),
            child: Text(
              '${type.bottleType} · ₱${type.price.toStringAsFixed(2)}',
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel scan'),
        ),
      ],
    ),
  );
  if (type == null) throw Exception('Scan cancelled.');
  return ScanLookup(
    lookup.condition,
    {
      ...lookup.transition,
      'bottleTypeId': type.bottleTypeId,
      'bottleType': type.bottleType,
      'price': type.price,
    },
    vehicle: lookup.vehicle,
    isNewUnregistered: true,
  );
}
