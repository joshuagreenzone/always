class Refill {
  final int refillId;
  final int bottleId;
  final String bottleNumber;
  final int bottleTypeId;
  final String bottleType;
  final double price;
  final DateTime refillDateTime;

  Refill({
    required this.refillId,
    required this.bottleId,
    required this.bottleNumber,
    required this.bottleTypeId,
    required this.bottleType,
    required this.price,
    required this.refillDateTime,
  });

  factory Refill.fromJson(Map<String, dynamic> json) {
    return Refill(
      refillId: int.parse(json['RefillID'].toString()),
      bottleId: int.parse(json['BottleID'].toString()),
      bottleNumber: json['BottleNumber'].toString(),
      bottleTypeId: int.parse(json['BottleTypeID'].toString()),
      bottleType: json['BottleType'].toString(),
      price: double.parse(json['Price'].toString()),
      refillDateTime: DateTime.parse(json['RefillDateTime'].toString()),
    );
  }
}
