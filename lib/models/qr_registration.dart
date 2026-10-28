bool isUnregisteredQr(String number) {
  final match = RegExp(
    r'^(A|RG|SG)-[0-9]{4}$',
    caseSensitive: false,
  ).firstMatch(number);
  return match == null || match.end != number.length;
}
