class BottleType {
  final int bottleTypeId;
  final String bottleType;
  final double price;

  BottleType({
    required this.bottleTypeId,
    required this.bottleType,
    required this.price,
  });

  factory BottleType.fromJson(Map<String, dynamic> json) {
    return BottleType(
      bottleTypeId: int.parse(json['BottleTypeID'].toString()),
      bottleType: json['BottleType'],
      price: double.parse(json['Price'].toString()),
    );
  }
}
