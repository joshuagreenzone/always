$root = 'C:\xampp\htdocs\gitlabCodes\alwaysweb'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$jsPath = Join-Path $root 'public\theme\js\borrow-dispenser.js'
$js = [System.IO.File]::ReadAllText($jsPath)
$js = [regex]::Replace($js, "Number\(row\.Amount\) === 0 \? '[^']*' : money\(row\.(Paid|Balance)\)", "Number(row.Amount) === 0 ? '-' : money(row.`$1)")
[System.IO.File]::WriteAllText($jsPath, $js, $utf8)

$testPath = Join-Path $root 'tests\dispenser_borrowing_integration.php'
$test = [System.IO.File]::ReadAllText($testPath).Replace("`r`n", "`n")
$old = "    checkBorrowing(`$createdBorrowing && `$createdBorrowing['Status'] === 'RETURNED', 'Return did not release the borrowing.');`n"
$new = @'
    checkBorrowing($createdBorrowing && $createdBorrowing['Status'] === 'RETURNED', 'Return did not release the borrowing.');

    $insert->execute([$customer, $type, 16]);
    $freeOrder = (int) $db->lastInsertId();
    $freeBorrowing = $service->create(['customerId' => $customer, 'orderId' => $freeOrder, 'dispenserNumber' => $dispenser['DispenserNumber'], 'monthlyFee' => '0'], $actor);
    $service->onScan((int) $dispenser['DispenserID'], 'DELIVERY_SCAN', $customer);
    $freeBills = array_values(array_filter($service->listing()['bills'], static fn ($row) => (int) $row['BorrowingID'] === (int) $freeBorrowing['borrowingId']));
    checkBorrowing(count($freeBills) === 1 && (float) $freeBills[0]['Amount'] === 0.0 && (float) $freeBills[0]['Balance'] === 0.0, 'Free monthly bill is wrong.');
    try {
        $service->pay(['billId' => $freeBills[0]['BillID'], 'amount' => '1', 'type' => 'CASH'], $actor);
        throw new RuntimeException('A payment was accepted for a free rental bill.');
    } catch (DomainException $expected) {}
    $service->onScan((int) $dispenser['DispenserID'], 'PICKUP_SCAN', $customer);
    $service->onScan((int) $dispenser['DispenserID'], 'RETURN_SCAN', $customer);
'@
if ($test.Contains($old)) {
    $test = $test.Replace($old, $new)
} elseif (-not $test.Contains("'Free monthly bill is wrong.'")) {
    throw 'Could not find the test insertion point.'
}
[System.IO.File]::WriteAllText($testPath, $test, $utf8)
