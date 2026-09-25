class RiderTransaction {
  final int orderId;
  final String transactionType;
  final String customerName;
  final String customerAddress;
  final String bottleType;
  final int quantity;
  final double unitPrice;
  final double totalAmount;
  final double paidAmount;
  final double balance;
  final String paymentStatus;
  final String dateTime;

  RiderTransaction({
    required this.orderId,
    required this.transactionType,
    required this.customerName,
    required this.customerAddress,
    required this.bottleType,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.paidAmount,
    required this.balance,
    required this.paymentStatus,
    required this.dateTime,
  });

  factory RiderTransaction.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    int toInt(dynamic value) {
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return RiderTransaction(
      orderId: toInt(json['OrderID']),
      transactionType: json['TransactionType']?.toString() ?? '',
      customerName: json['CustomerName']?.toString() ?? '',
      customerAddress: json['CustomerAddress']?.toString() ?? '',
      bottleType: json['BottleType']?.toString() ?? '',
      quantity: toInt(json['Quantity']),
      unitPrice: toDouble(json['UnitPrice']),
      totalAmount: toDouble(json['TotalAmount']),
      paidAmount: toDouble(json['PaidAmount']),
      balance: toDouble(json['Balance']),
      paymentStatus: json['PaymentStatus']?.toString() ?? 'UNPAID',
      dateTime: json['TransactionDateTime']?.toString() ?? '',
    );
  }
}
