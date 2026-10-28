class BottleRepairPart {
  final int supplyId;
  final String name;
  final int quantityOnHand;
  const BottleRepairPart({
    required this.supplyId,
    required this.name,
    required this.quantityOnHand,
  });
  factory BottleRepairPart.fromJson(Map<String, dynamic> json) =>
      BottleRepairPart(
        supplyId: int.parse(json['supplyId'].toString()),
        name: json['name'].toString(),
        quantityOnHand: int.parse(json['quantityOnHand'].toString()),
      );
}

class BottleCondition {
  static const states = ['HEALTHY', 'MISSING', 'DAMAGED'];

  final String bottleNumber;
  final String bottleOwner;

  String get ownerLabel =>
      bottleOwner == 'CUSTOMER' ? 'Customer bottle' : 'Company bottle';
  final String condition;
  final List<BottleRepairPart> repairParts;
  final int partsUsed;
  final String? note;
  final DateTime? updatedAt;
  final bool needsRefillAfterRecovery;

  const BottleCondition({
    required this.bottleNumber,
    this.bottleOwner = 'COMPANY',
    required this.condition,
    this.note,
    this.repairParts = const [],
    this.partsUsed = 0,
    this.updatedAt,
    this.needsRefillAfterRecovery = false,
  });

  bool get isHealthy => condition == 'HEALTHY';

  factory BottleCondition.fromJson(Map<String, dynamic> json) {
    final condition = json['condition']?.toString();
    if (!states.contains(condition)) {
      throw const FormatException('Invalid bottle state returned by server.');
    }
    return BottleCondition(
      bottleOwner: json['bottleOwner']?.toString() ?? 'COMPANY',
      bottleNumber: json['bottleNumber'].toString(),
      condition: condition!,
      note: json['note']?.toString(),
      repairParts: (json['repairParts'] as List? ?? [])
          .map(
            (part) => BottleRepairPart.fromJson(
              Map<String, dynamic>.from(part as Map),
            ),
          )
          .toList(),
      partsUsed: int.tryParse(json['partsUsed']?.toString() ?? '') ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      needsRefillAfterRecovery: json['needsRefillAfterRecovery'] == true,
    );
  }
}
