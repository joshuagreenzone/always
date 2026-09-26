class AssignedOrderItem {
  final int orderItemId;
  final int bottleTypeId;
  final String bottleType;
  final int quantity;
  final double unitPrice;
  final double totalAmount;

  const AssignedOrderItem({
    required this.orderItemId,
    required this.bottleTypeId,
    required this.bottleType,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
  });

  factory AssignedOrderItem.fromJson(Map<String, dynamic> json) {
    final quantity = int.parse(json['Quantity'].toString());
    final unitPrice = double.parse(json['UnitPrice'].toString());

    return AssignedOrderItem(
      orderItemId: int.parse(json['OrderItemID'].toString()),
      bottleTypeId: int.parse(json['BottleTypeID'].toString()),
      bottleType: json['BottleType'].toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      totalAmount: json['TotalAmount'] != null
          ? double.parse(json['TotalAmount'].toString())
          : quantity * unitPrice,
    );
  }
}

class AssignedOrder {
  final int orderId;
  final int customerId;
  final String customerName;

  final List<AssignedOrderItem> items;

  final int totalQuantity;
  final double totalAmount;

  final DateTime orderDateTime;
  final String orderStatus;
  final String paymentStatus;

  final int deliveryId;
  final DateTime deliveryDateTime;
  final String deliveryStatus;

  const AssignedOrder({
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.items,
    required this.totalQuantity,
    required this.totalAmount,
    required this.orderDateTime,
    required this.orderStatus,
    required this.paymentStatus,
    required this.deliveryId,
    required this.deliveryDateTime,
    required this.deliveryStatus,
  });

  factory AssignedOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] ?? json['Items'] ?? [];

    final items = (rawItems as List)
        .map(
          (item) => AssignedOrderItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();

    final calculatedQuantity = items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final calculatedAmount = items.fold<double>(
      0,
      (sum, item) => sum + item.totalAmount,
    );

    return AssignedOrder(
      orderId: int.parse(json['OrderID'].toString()),
      customerId: int.parse(json['CustomerID'].toString()),
      customerName: json['CustomerName'].toString(),

      items: items,

      totalQuantity: json['TotalQuantity'] != null
          ? int.parse(json['TotalQuantity'].toString())
          : calculatedQuantity,

      totalAmount: json['TotalAmount'] != null
          ? double.parse(json['TotalAmount'].toString())
          : calculatedAmount,

      orderDateTime: DateTime.parse(json['OrderDateTime'].toString()),

      orderStatus: json['OrderStatus'].toString(),
      paymentStatus: json['PaymentStatus'].toString(),

      deliveryId: int.parse(json['DeliveryID'].toString()),

      deliveryDateTime: DateTime.parse(json['DeliveryDateTime'].toString()),

      deliveryStatus: json['DeliveryStatus'].toString(),
    );
  }
}
