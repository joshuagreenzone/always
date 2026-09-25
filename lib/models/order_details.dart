class OrderDetails {
  final int orderId;
  final int customerId;
  final String customerName;
  final int bottleTypeId;
  final String bottleType;
  final int quantity;
  final double unitPrice;
  final double totalAmount;
  final DateTime orderDateTime;
  final String orderStatus;
  final String paymentStatus;
  final int deliveryId;
  final DateTime deliveryDateTime;
  final String deliveryStatus;

  OrderDetails({
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.bottleTypeId,
    required this.bottleType,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.orderDateTime,
    required this.orderStatus,
    required this.paymentStatus,
    required this.deliveryId,
    required this.deliveryDateTime,
    required this.deliveryStatus,
  });

  factory OrderDetails.fromJson(Map<String, dynamic> json) {
    return OrderDetails(
      orderId: int.parse(json['OrderID'].toString()),
      customerId: int.parse(json['CustomerID'].toString()),
      customerName: json['CustomerName'].toString(),
      bottleTypeId: int.parse(json['BottleTypeID'].toString()),
      bottleType: json['BottleType'].toString(),
      quantity: int.parse(json['Quantity'].toString()),
      unitPrice: double.parse(json['UnitPrice'].toString()),
      totalAmount: double.parse(json['TotalAmount'].toString()),
      orderDateTime: DateTime.parse(json['OrderDateTime'].toString()),
      orderStatus: json['OrderStatus'].toString(),
      paymentStatus: json['PaymentStatus'].toString(),
      deliveryId: int.parse(json['DeliveryID'].toString()),
      deliveryDateTime: DateTime.parse(json['DeliveryDateTime'].toString()),
      deliveryStatus: json['DeliveryStatus'].toString(),
    );
  }
}
