$root = 'C:\xampp\htdocs\gitlabCodes\alwaysweb'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$jsPath = Join-Path $root 'public\theme\js\borrow-dispenser.js'
$js = [System.IO.File]::ReadAllText($jsPath)
function Replace-Once([string]$content, [string]$old, [string]$new, [string]$label) {
    $count = ([regex]::Matches($content, [regex]::Escape($old))).Count
    if ($count -ne 1) { throw "Expected one match for $label, found $count" }
    return $content.Replace($old, $new)
}
$js = Replace-Once $js '<td>${money(row.MonthlyFee)}</td>' '<td>${Number(row.MonthlyFee) === 0 ? ''Free'' : money(row.MonthlyFee)}</td>' 'borrowing fee cell'
$oldBalance = '${money(bills.filter((bill) => Number(bill.BorrowingID) === Number(row.BorrowingID)).reduce((sum, bill) => sum + Number(bill.Balance || 0), 0))}'
$newBalance = '${Number(row.MonthlyFee) === 0 ? ''Free'' : money(bills.filter((bill) => Number(bill.BorrowingID) === Number(row.BorrowingID)).reduce((sum, bill) => sum + Number(bill.Balance || 0), 0))}'
$js = Replace-Once $js $oldBalance $newBalance 'borrowing balance cell'
$oldAmounts = '<td>${money(row.Amount)}</td><td>${money(row.Paid)}</td><td><strong>${money(row.Balance)}</strong></td>'
$newAmounts = '<td>${Number(row.Amount) === 0 ? ''Free'' : money(row.Amount)}</td><td>${Number(row.Amount) === 0 ? ''—'' : money(row.Paid)}</td><td><strong>${Number(row.Amount) === 0 ? ''—'' : money(row.Balance)}</strong></td>'
$js = Replace-Once $js $oldAmounts $newAmounts 'monthly bill amount cells'
$js = Replace-Once $js 'Number(row.Balance) > 0 ?' 'Number(row.Amount) === 0 ? ''<span class="borrow-paid">Free</span>'' : Number(row.Balance) > 0 ?' 'monthly bill payment cell'
[System.IO.File]::WriteAllText($jsPath, $js, $utf8)

$migrationPath = Join-Path $root 'app\syawla_mobile_api\migrations\20261017_dispenser_free_monthly_fee.sql'
$migration = @'
-- Allow zero-cost dispenser rental and retain visible zero-value monthly bills.
ALTER TABLE dispenser_borrowing
    DROP CONSTRAINT chk_dispenser_borrowing_fee,
    ADD CONSTRAINT chk_dispenser_borrowing_fee CHECK (MonthlyFee >= 0);

ALTER TABLE dispenser_borrowing_bill
    DROP CONSTRAINT chk_dispenser_borrowing_bill_amount,
    ADD CONSTRAINT chk_dispenser_borrowing_bill_amount CHECK (Amount >= 0);
'@
[System.IO.File]::WriteAllText($migrationPath, $migration, $utf8)
