class BottleRegistration {
  final int bottleId;
  final String bottleNumber;
  final int bottleTypeId;
  final String bottleType;
  final String bottleBrand;
  final String bottleCondition;
  final double bottleCost;
  final DateTime bottleRegDateTime;

  BottleRegistration({
    required this.bottleId,
    required this.bottleNumber,
    required this.bottleTypeId,
    required this.bottleType,
    required this.bottleBrand,
    required this.bottleCondition,
    required this.bottleCost,
    required this.bottleRegDateTime,
  });

  factory BottleRegistration.fromJson(Map<String, dynamic> json) {
    return BottleRegistration(
      bottleId: _parseInt(json['bottleId']),
      bottleNumber: json['bottleNumber']?.toString() ?? '',
      bottleTypeId: _parseInt(json['bottleTypeId']),
      bottleType: json['bottleType']?.toString() ?? '',
      bottleBrand: json['bottleBrand']?.toString() ?? '',
      bottleCondition: json['bottleCondition']?.toString() ?? '',
      bottleCost: _parseDouble(json['bottleCost']),
      bottleRegDateTime: _parseDateTime(json['bottleRegDateTime']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final parsed = int.tryParse(value.toString().trim());

    return parsed ?? 0;
  }

  static double _parseDouble(dynamic value) {
    if (value == null) {
      return 0.0;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    final parsed = double.tryParse(value.toString().trim());

    return parsed ?? 0.0;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) {
      return DateTime.now();
    }

    final parsed = DateTime.tryParse(value.toString());

    return parsed ?? DateTime.now();
  }
}
