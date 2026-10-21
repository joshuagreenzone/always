class BottleCondition {
  static const states = ['HEALTHY', 'MISSING', 'DAMAGED'];

  final String bottleNumber;
  final String bottleOwner;

  String get ownerLabel =>
      bottleOwner == 'CUSTOMER' ? 'Customer bottle' : 'Company bottle';
  final String condition;
  final String? note;
  final DateTime? updatedAt;
  final bool needsRefillAfterRecovery;

  const BottleCondition({
    required this.bottleNumber,
    this.bottleOwner = 'COMPANY',
    required this.condition,
    this.note,
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
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      needsRefillAfterRecovery: json['needsRefillAfterRecovery'] == true,
    );
  }
}
