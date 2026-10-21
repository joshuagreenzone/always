$ErrorActionPreference = 'Stop'
$apiRoot = 'C:\xampp\htdocs\gitlabCodes\alwaysweb\app\syawla_mobile_api'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$paymentPath = Join-Path $apiRoot 'api\rider\create_payment.php'
$payment = [IO.File]::ReadAllText($paymentPath)
if (!$payment.Contains("require_once __DIR__ . '/../../services/payment_billing.php';")) {
    $payment = $payment.Replace("require_once __DIR__ . '/../../services/account_roles.php';", "require_once __DIR__ . '/../../services/account_roles.php';`r`nrequire_once __DIR__ . '/../../services/payment_billing.php';")
}
$oldAmount = '$deliveredAmount = round($deliveredAmount, 2);'
$newAmount = '$deliveredAmount = riderBillableAmount($db, $orderId);'
if (!$payment.Contains($oldAmount) -and !$payment.Contains($newAmount)) { throw 'Unexpected payment billing source.' }
$payment = $payment.Replace($oldAmount, "// Use immutable promo bundles and confirmed delivered quantities, as web finance does.`r`n    $newAmount")
[IO.File]::WriteAllText($paymentPath, $payment, $utf8)
$pickupPath = Join-Path $apiRoot 'api\rider\complete_pickup.php'
$pickup = [IO.File]::ReadAllText($pickupPath)
if (!$pickup.Contains("require_once __DIR__ . '/../../services/payment_billing.php';")) {
    $pickup = $pickup.Replace("require_once __DIR__ . '/../../services/bottle_cycle.php';", "require_once __DIR__ . '/../../services/bottle_cycle.php';`r`nrequire_once __DIR__ . '/../../services/payment_billing.php';")
}
$pattern = '\$deliveredAmount = round\(\s*\(float\) \$deliveredValueStmt->fetchColumn\(\),\s*2\s*\);'
if (![regex]::IsMatch($pickup, $pattern) -and !$pickup.Contains($newAmount)) { throw 'Unexpected pickup billing source.' }
$pickup = [regex]::Replace($pickup, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) '$deliveredAmount = riderBillableAmount($db, $orderId);' })
[IO.File]::WriteAllText($pickupPath, $pickup, $utf8)
Write-Output 'Updated active CI4 mobile payment and pickup billing endpoints.'
