class PickupOrder {
  final int deliveryId;
  final int orderId;
  final int accId;

  final int customerId;
  final String customerName;

  final int bottleTypeId;
  final String bottleType;

  final int quantity;
  final int deliveredBottleCount;
  final int pickedUpBottleCount;

  final DateTime deliveryDateTime;
  final String deliveryStatus;

  PickupOrder({
    required this.deliveryId,
    required this.orderId,
    required this.accId,
    required this.customerId,
    required this.customerName,
    required this.bottleTypeId,
    required this.bottleType,
    required this.quantity,
    required this.deliveredBottleCount,
    required this.pickedUpBottleCount,
    required this.deliveryDateTime,
    required this.deliveryStatus,
  });

  factory PickupOrder.fromJson(Map<String, dynamic> json) {
    return PickupOrder(
      deliveryId: int.parse(json['DeliveryID'].toString()),

      orderId: int.parse(json['OrderID'].toString()),

      accId: int.parse(json['AccID'].toString()),

      customerId: int.parse(json['CustomerID'].toString()),

      customerName: json['CustomerName'].toString(),

      bottleTypeId: int.parse(json['BottleTypeID'].toString()),

      bottleType: json['BottleType'].toString(),

      quantity: int.parse(json['Quantity'].toString()),

      deliveredBottleCount: int.parse(json['DeliveredBottleCount'].toString()),

      pickedUpBottleCount: int.parse(json['PickedUpBottleCount'].toString()),

      deliveryDateTime: DateTime.parse(json['DeliveryDateTime'].toString()),

      deliveryStatus: json['DeliveryStatus'].toString(),
    );
  }
}
