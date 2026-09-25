class Account {
  final int accId;
  final String accName;
  final String accEmail;
  final String accUsername;
  final String accType;

  Account({
    required this.accId,
    required this.accName,
    required this.accEmail,
    required this.accUsername,
    required this.accType,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      accId: int.parse(json['AccID'].toString()),
      accName: json['AccName'],
      accEmail: json['AccEmail'],
      accUsername: json['AccUsername'],
      accType: json['AccType'],
    );
  }
}
