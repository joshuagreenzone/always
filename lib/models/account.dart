class Account {
  final int accId;
  final String accName;
  final String accEmail;
  final String accUsername;
  final String accType;
  final List<String> accRoles;

  Account({
    required this.accId,
    required this.accName,
    required this.accEmail,
    required this.accUsername,
    required this.accType,
    List<String>? accRoles,
  }) : accRoles = accRoles ?? [accType];

  bool hasRole(String role) =>
      accRoles.any((value) => value.toUpperCase() == role.toUpperCase());

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      accId: int.parse(json['AccID'].toString()),
      accName: json['AccName'],
      accEmail: json['AccEmail'],
      accUsername: json['AccUsername'],
      accType: json['AccType'],
      accRoles: json['AccRoles'] is List
          ? (json['AccRoles'] as List).map((role) => role.toString()).toList()
          : null,
    );
  }
}
