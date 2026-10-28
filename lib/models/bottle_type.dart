class BottleType {
  final int bottleTypeId;
  final String bottleType;
  final double price;
  final String bottlePrefix;

  BottleType({
    required this.bottleTypeId,
    required this.bottleType,
    required this.price,
    this.bottlePrefix = '',
  });

  factory BottleType.fromJson(Map<String, dynamic> json) {
    return BottleType(
      bottleTypeId: int.parse(json['BottleTypeID'].toString()),
      bottleType: json['BottleType'],
      price: double.parse(json['Price'].toString()),
      bottlePrefix: json['BottlePrefix']?.toString().trim() ?? '',
    );
  }

  String get numberExample => '$bottlePrefix-0000';
  String get acceptedNumberExamples =>
      bottlePrefix.isEmpty || bottlePrefix == 'A'
      ? 'A-0000 (legacy QR)'
      : '$numberExample or A-0000 (legacy QR)';

  bool acceptsNumber(String number) {
    // Legacy A codes use the bottle type selected during registration.
    if (RegExp(r'^A-[0-9]{4}$').hasMatch(number) && number.length == 6) {
      return true;
    }
    if (bottlePrefix.isEmpty) return false;
    final match = RegExp('^${RegExp.escape(bottlePrefix)}-[0-9]{4}\$')
        .firstMatch(number);
    return match != null && match.end == number.length;
  }
}
