<?php
require_once __DIR__ . '/../services/bottle_registration_number.php';
foreach (['A-0000', 'A-0001', 'A-9999'] as $number) {
    if (!isRegistrationBottleNumber($number, 'A')) throw new RuntimeException('Valid number rejected: ' . $number);
}
foreach (['', 'B-0001', 'a-0001', 'A0001', 'A-001', 'A-00001', 'A-ABCD', "A-0001\n", ' A-0001', 'https://example.com/A-0001'] as $number) {
    if (isRegistrationBottleNumber($number, 'A')) throw new RuntimeException('Invalid number accepted: ' . $number);
}
if (!isRegistrationBottleNumber('RG-0001', 'RG') || isRegistrationBottleNumber('SG-0001', 'RG')
    || !isRegistrationBottleNumber('A+-0001', 'A+') || isRegistrationBottleNumber('AA-0001', 'A+')
    || isRegistrationBottleNumber('RG-0001', '')) throw new RuntimeException('Prefix validation failed.');
echo "PASS: exact prefixes, four digits, invalid formats, literal matching, missing prefixes.\n";

foreach (['SG', 'RG', ''] as $prefix) {
    if (!isRegistrationBottleNumber('A-0000', $prefix) || !isRegistrationBottleNumber('A-1234', $prefix)
        || isRegistrationBottleNumber('A-123', $prefix) || isRegistrationBottleNumber('A-12345', $prefix)) {
        throw new RuntimeException('Legacy A code validation failed.');
    }
}
echo "PASS: legacy A codes work for either selected type.\n";
