$root = 'C:\xampp\htdocs\gitlabCodes\alwaysweb'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Replace-Once([string]$content, [string]$old, [string]$new, [string]$label) {
    $count = ([regex]::Matches($content, [regex]::Escape($old))).Count
    if ($count -eq 0 -and ([regex]::Matches($content, [regex]::Escape($new))).Count -eq 1) { return $content }
    if ($count -ne 1) { throw "Expected one match for $label, found $count" }
    return $content.Replace($old, $new)
}

$servicePath = Join-Path $root 'app\Services\DispenserBorrowingService.php'
$service = [System.IO.File]::ReadAllText($servicePath)
$service = Replace-Once $service '(float) $rawFee <= 0' '(float) $rawFee < 0' 'raw fee validation'
$service = Replace-Once $service 'Enter a positive monthly dispenser fee.' 'Enter a zero or positive monthly dispenser fee.' 'fee validation message'
$old = 'if ($fee <= 0 || mb_strlen($notes) > 1000) throw new InvalidArgumentException(''Check the monthly fee and notes.'');'
$new = 'if ($fee < 0 || mb_strlen($notes) > 1000) throw new InvalidArgumentException(''Check the monthly fee and notes.'');'
$service = Replace-Once $service $old $new 'rounded fee validation'
[System.IO.File]::WriteAllText($servicePath, $service, $utf8)

$viewPath = Join-Path $root 'app\Views\orders\borrow-dispenser.php'
$view = [System.IO.File]::ReadAllText($viewPath)
$old = '<input id="borrowMonthlyFee" name="monthlyFee" type="number" min="0.01" max="9999999999.99" step="0.01" placeholder="0.00" required><small>The bottle order keeps its own payment balance.</small>'
$new = '<input id="borrowMonthlyFee" name="monthlyFee" type="number" min="0" max="9999999999.99" step="0.01" placeholder="0.00" required><small>Enter 0 for a free dispenser rental. The bottle order keeps its own payment balance.</small>'
$view = Replace-Once $view $old $new 'monthly fee input'
[System.IO.File]::WriteAllText($viewPath, $view, $utf8)

$jsPath = Join-Path $root 'public\theme\js\borrow-dispenser.js'
$js = [System.IO.File]::ReadAllText($jsPath).Replace("`r`n", "`n")
$oldBorrow = '<td>${money(row.MonthlyFee)}</td>' + "`n" + '            <td><button type="button" class="borrow-pay-button" data-borrowing-id="${Number(row.BorrowingID)}">${money(bills.filter((bill) => Number(bill.BorrowingID) === Number(row.BorrowingID)).reduce((sum, bill) => sum + Number(bill.Balance || 0), 0))} · View bills</button></td>'
$newBorrow = '<td>${Number(row.MonthlyFee) === 0 ? ''Free'' : money(row.MonthlyFee)}</td>' + "`n" + '            <td><button type="button" class="borrow-pay-button" data-borrowing-id="${Number(row.BorrowingID)}">${Number(row.MonthlyFee) === 0 ? ''Free'' : money(bills.filter((bill) => Number(bill.BorrowingID) === Number(row.BorrowingID)).reduce((sum, bill) => sum + Number(bill.Balance || 0), 0))} · View bills</button></td>'
$js = Replace-Once $js $oldBorrow $newBorrow 'borrowing fee and balance display'
$oldBill = '<td>${money(row.Amount)}</td><td>${money(row.Paid)}</td><td><strong>${money(row.Balance)}</strong></td>' + "`n" + '            <td>${Number(row.Balance) > 0 ? `<button type="button" class="borrow-pay-button" data-bill-id="${Number(row.BillID)}">Record payment</button>` : ''<span class="borrow-paid">Paid</span>''}</td>'
$newBill = '<td>${Number(row.Amount) === 0 ? ''Free'' : money(row.Amount)}</td><td>${Number(row.Amount) === 0 ? ''—'' : money(row.Paid)}</td><td><strong>${Number(row.Amount) === 0 ? ''—'' : money(row.Balance)}</strong></td>' + "`n" + '            <td>${Number(row.Amount) === 0 ? ''<span class="borrow-paid">Free</span>'' : Number(row.Balance) > 0 ? `<button type="button" class="borrow-pay-button" data-bill-id="${Number(row.BillID)}">Record payment</button>` : ''<span class="borrow-paid">Paid</span>''}</td>'
$js = Replace-Once $js $oldBill $newBill 'monthly bill free display'
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
