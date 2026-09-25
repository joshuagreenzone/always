class Bottle {
  final int bottleId;
  final String bottleNumber;
  final int bottleTypeId;
  final String bottleType;
  final double price;
  final DateTime bottleRegDateTime;

  Bottle({
    required this.bottleId,
    required this.bottleNumber,
    required this.bottleTypeId,
    required this.bottleType,
    required this.price,
    required this.bottleRegDateTime,
  });

  factory Bottle.fromJson(Map<String, dynamic> json) {
    return Bottle(
      bottleId: int.parse(json['BottleID'].toString()),
      bottleNumber: json['BottleNumber'].toString(),
      bottleTypeId: int.parse(json['BottleTypeID'].toString()),
      bottleType: json['BottleType'].toString(),
      price: double.parse(json['Price'].toString()),
      bottleRegDateTime: DateTime.parse(json['BottleRegDateTime'].toString()),
    );
  }
}
