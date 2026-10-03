class PickupBottleType {
  final int bottleTypeId;
  final String bottleType;
  final int deliveredBottleCount;
  final int pickedUpBottleCount;
  final int remainingBottleCount;

  const PickupBottleType({
    required this.bottleTypeId,
    required this.bottleType,
    required this.deliveredBottleCount,
    required this.pickedUpBottleCount,
    required this.remainingBottleCount,
  });

  factory PickupBottleType.fromJson(Map<String, dynamic> json) {
    return PickupBottleType(
      bottleTypeId: _toInt(json['BottleTypeID'] ?? json['bottleTypeId']),
      bottleType: (json['BottleType'] ?? json['bottleType'] ?? 'Bottles')
          .toString(),
      deliveredBottleCount: _toInt(
        json['DeliveredBottleCount'] ?? json['deliveredBottleCount'],
      ),
      pickedUpBottleCount: _toInt(
        json['PickedUpBottleCount'] ?? json['pickedUpBottleCount'],
      ),
      remainingBottleCount: _toInt(
        json['RemainingBottleCount'] ?? json['remainingBottleCount'],
      ),
    );
  }
}

class PickupOrder {
  final int deliveryId;
  final int orderId;
  final int accId;
  final int customerId;
  final String customerName;
  final List<PickupBottleType> bottleTypes;
  final int quantity;
  final int deliveredBottleCount;
  final int pickedUpBottleCount;
  final int remainingBottleCount;
  final DateTime deliveryDateTime;
  final String deliveryStatus;

  const PickupOrder({
    required this.deliveryId,
    required this.orderId,
    required this.accId,
    required this.customerId,
    required this.customerName,
    required this.bottleTypes,
    required this.quantity,
    required this.deliveredBottleCount,
    required this.pickedUpBottleCount,
    required this.remainingBottleCount,
    required this.deliveryDateTime,
    required this.deliveryStatus,
  });

  // Backward compatibility for screens that still expect one bottle type.
  int get bottleTypeId =>
      bottleTypes.isNotEmpty ? bottleTypes.first.bottleTypeId : 0;

  String get bottleType =>
      bottleTypes.isNotEmpty ? bottleTypes.first.bottleType : 'Bottles';

  factory PickupOrder.fromJson(Map<String, dynamic> json) {
    final rawBottleTypes = json['BottleTypes'] ?? json['bottleTypes'];

    final bottleTypes = rawBottleTypes is List
        ? rawBottleTypes
              .whereType<Map>()
              .map(
                (item) =>
                    PickupBottleType.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <PickupBottleType>[];

    return PickupOrder(
      deliveryId: _toInt(json['DeliveryID'] ?? json['deliveryId']),
      orderId: _toInt(json['OrderID'] ?? json['orderId']),
      accId: _toInt(json['AccID'] ?? json['accId']),
      customerId: _toInt(json['CustomerID'] ?? json['customerId']),
      customerName: (json['CustomerName'] ?? json['customerName'] ?? '')
          .toString(),
      bottleTypes: bottleTypes,
      quantity: _toInt(json['Quantity'] ?? json['quantity']),
      deliveredBottleCount: _toInt(
        json['DeliveredBottleCount'] ?? json['deliveredBottleCount'],
      ),
      pickedUpBottleCount: _toInt(
        json['PickedUpBottleCount'] ?? json['pickedUpBottleCount'],
      ),
      remainingBottleCount: _toInt(
        json['RemainingBottleCount'] ?? json['remainingBottleCount'],
      ),
      deliveryDateTime:
          DateTime.tryParse(
            (json['DeliveryDateTime'] ?? json['deliveryDateTime'] ?? '')
                .toString(),
          ) ??
          DateTime.now(),
      deliveryStatus: (json['DeliveryStatus'] ?? json['deliveryStatus'] ?? '')
          .toString(),
    );
  }
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
