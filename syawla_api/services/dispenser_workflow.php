<?php

final class DispenserWorkflow
{
    public function __construct(private PDO $db) {}

    private function one(string $sql, array $args = []): ?array
    {
        $stmt = $this->db->prepare($sql);
        $stmt->execute($args);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    private function all(string $sql, array $args = []): array
    {
        $stmt = $this->db->prepare($sql);
        $stmt->execute($args);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    private function actor(int $id, array $roles): void
    {
        if ($id <= 0 || !$this->one('SELECT 1 FROM account_roles WHERE AccID = ? AND Role IN (' . implode(',', array_fill(0, count($roles), '?')) . ') LIMIT 1', [$id, ...$roles])) {
            throw new DomainException('This account cannot record dispenser activity.');
        }
    }

    private function dispenser(string $number, bool $lock = false): array
    {
        $row = $this->one('SELECT * FROM dispensers WHERE DispenserNumber = ?' . ($lock ? ' FOR UPDATE' : ''), [$number]);
        if (!$row) throw new OutOfBoundsException('Dispenser not found.');
        return $row;
    }

    public function customers(): array
    {
        return $this->all('SELECT CustomerID AS customerId, CustomerName AS customerName FROM customers ORDER BY CustomerName');
    }

    public function inventory(): array
    {
        $rows = $this->all('SELECT d.*, c.CustomerName, a.AccName FROM dispensers d LEFT JOIN customers c ON c.CustomerID = d.CurrentCustomerID LEFT JOIN accounts a ON a.AccID = d.CurrentAccID ORDER BY d.DispenserID DESC');
        $counts = ['AVAILABLE' => 0, 'READY_TO_LOAD' => 0, 'LOADED' => 0, 'DELIVERED' => 0, 'PICKED_UP' => 0,
            'HEALTHY' => 0, 'DAMAGED' => 0, 'INOPERATIVE' => 0, 'MISSING' => 0];
        foreach ($rows as $row) {
            $counts[$row['LifecycleStatus']]++;
            if ($row['LifecycleStatus'] === 'AVAILABLE' && $row['PhysicalState'] === 'HEALTHY') $counts['READY_TO_LOAD']++;
            $counts[$row['PhysicalState']]++;
        }
        return ['dispensers' => $rows, 'counts' => $counts, 'customers' => $this->customers()];
    }

    public function history(string $number): array
    {
        $d = $this->dispenser($number);
        $id = (int) $d['DispenserID'];
        return [
            'dispenser' => $d,
            'deployments' => $this->all('SELECT dep.*, c.CustomerName FROM dispenser_deployment dep JOIN customers c ON c.CustomerID = dep.CustomerID WHERE dep.DispenserID = ? ORDER BY dep.DeploymentID DESC', [$id]),
            'scans' => $this->all('SELECT e.*, a.AccName, c.CustomerName FROM dispenser_scan_event e JOIN accounts a ON a.AccID = e.AccID LEFT JOIN customers c ON c.CustomerID = e.CustomerID WHERE e.DispenserID = ? ORDER BY e.ScanEventID DESC', [$id]),
            'states' => $this->all('SELECT h.*, a.AccName AS RecordedBy FROM dispenser_state_history h JOIN accounts a ON a.AccID = h.RecordedByAccID WHERE h.DispenserID = ? ORDER BY h.StateHistoryID DESC', [$id]),
            'maintenance' => $this->all('SELECT m.*, c.CustomerName, performer.AccName AS PerformedBy, recorder.AccName AS RecordedBy FROM dispenser_maintenance m LEFT JOIN customers c ON c.CustomerID = m.CustomerID LEFT JOIN accounts performer ON performer.AccID = m.PerformedByAccID JOIN accounts recorder ON recorder.AccID = m.RecordedByAccID WHERE m.DispenserID = ? ORDER BY m.MaintenanceID DESC', [$id]),
        ];
    }

    public function register(array $input): array
    {
        $number = strtoupper(trim((string) ($input['dispenserNumber'] ?? '')));
        $acquisition = strtoupper(trim((string) ($input['dispenserAcquisition'] ?? '')));
        $payment = strtoupper(trim((string) ($input['dispenserPaymentStatus'] ?? '')));
        $rawCost = $input['dispenserCost'] ?? null;
        $cost = $payment === 'FREE' ? 0.0 : (is_numeric($rawCost) ? round((float) $rawCost, 2) : null);
        if (!preg_match('/^[A-Z0-9][A-Z0-9-]{2,63}$/', $number)) throw new InvalidArgumentException('Use a unique dispenser number of 3 to 64 letters, numbers or dashes.');
        if (!in_array($acquisition, ['BRAND_NEW', 'SECOND_HAND'], true)) throw new InvalidArgumentException('Select whether the dispenser is brand new or second hand.');
        if (!in_array($payment, ['FREE', 'PAID', 'UNPAID'], true) || $cost === null || !is_finite($cost) || $cost < 0 || $cost > 9999999999.99 || ($payment === 'FREE' ? $cost !== 0.0 : $cost <= 0)) {
            throw new InvalidArgumentException('Select a payment status and enter a valid acquisition cost. Free dispensers must have a zero cost.');
        }
        if ($this->one('SELECT DispenserID FROM dispensers WHERE DispenserNumber = ?', [$number])) throw new DomainException('Dispenser number is already registered.');
        $stmt = $this->db->prepare('INSERT INTO dispensers (DispenserNumber, Brand, Model, DispenserAcquisition, DispenserCost, DispenserPaymentStatus) VALUES (?, ?, ?, ?, ?, ?)');
        $stmt->execute([$number, trim((string) ($input['brand'] ?? '')) ?: null,
            trim((string) ($input['model'] ?? '')) ?: null, $acquisition, $cost, $payment]);
        return $this->dispenser($number);
    }

    public function scan(array $input): array
    {
        $number = strtoupper(trim((string) ($input['dispenserNumber'] ?? '')));
        $event = strtoupper(trim((string) ($input['eventType'] ?? '')));
        $actor = (int) ($input['accId'] ?? 0);
        $customer = (int) ($input['customerId'] ?? 0);
        $reason = trim((string) ($input['jumpReason'] ?? ''));
        $steps = [
            'LOAD_SCAN' => ['AVAILABLE', 'LOADED', 'RETURN_SCAN'],
            'DELIVERY_SCAN' => ['LOADED', 'DELIVERED', 'LOAD_SCAN'],
            'PICKUP_SCAN' => ['DELIVERED', 'PICKED_UP', 'DELIVERY_SCAN'],
            'RETURN_SCAN' => ['PICKED_UP', 'AVAILABLE', 'PICKUP_SCAN'],
        ];
        if (!isset($steps[$event]) || $number === '') throw new InvalidArgumentException('Select a dispenser and valid scan step.');
        $this->actor($actor, $event === 'RETURN_SCAN' ? ['RIDER', 'STATION_WORKER'] : ['RIDER']);
        if (strlen($reason) > 1000) throw new InvalidArgumentException('Jump reason is too long.');
        $this->db->beginTransaction();
        try {
            $d = $this->dispenser($number, true);
            $assignment = null;
            if (in_array($event, ['LOAD_SCAN','DELIVERY_SCAN'], true)) {
                $borrow = $this->one("SELECT BorrowingID FROM dispenser_borrowing WHERE ActiveDispenserID=? AND Status='RESERVED' FOR UPDATE", [$d['DispenserID']]);
                if (!$borrow) throw new DomainException('Reserve this dispenser through Orders and assign a rider before loading or delivery.');
                $assignment = $this->one("SELECT AssignmentID,RiderAccID,Status FROM dispenser_delivery_assignment WHERE BorrowingID=? AND Status IN ('ASSIGNED','OUT_FOR_DELIVERY') ORDER BY AssignmentID DESC LIMIT 1 FOR UPDATE", [$borrow['BorrowingID']]);
                if (!$assignment) throw new DomainException('Assign an active dispenser delivery to a rider before scanning.');
                if ((int)$assignment['RiderAccID'] !== $actor) throw new DomainException('This dispenser delivery is assigned to another rider. Ask the dispatcher to reassign it.');
            }

            if ($d['PhysicalState'] === 'MISSING' ||
                (in_array($event, ['LOAD_SCAN', 'DELIVERY_SCAN'], true) && $d['PhysicalState'] !== 'HEALTHY')) {
                throw new DomainException('This dispenser is not healthy and available for deployment.');
            }
            if ($event === 'DELIVERY_SCAN' && $d['LifecycleStatus'] === 'LOADED' && (int) $d['CurrentAccID'] !== $actor) {
                throw new DomainException('Only the rider who loaded this dispenser can scan its delivery.');
            }
            $previous = $this->one('SELECT ScanEventID, EventType FROM dispenser_scan_event WHERE DispenserID = ? ORDER BY ScanEventID DESC LIMIT 1', [$d['DispenserID']]);
            $expected = $steps[$event][0];
            $jump = $d['LifecycleStatus'] !== $expected;
            if ($jump && $reason === '') throw new DomainException('This scan skips the expected step. Enter a reason.');
            if (!$jump && $reason !== '') throw new InvalidArgumentException('A jump reason is only used when a step is skipped.');
            if ($event === 'DELIVERY_SCAN') {
                if ($customer <= 0 || !$this->one('SELECT 1 FROM customers WHERE CustomerID = ?', [$customer])) throw new InvalidArgumentException('Select the customer receiving this dispenser.');
            } elseif ($event === 'PICKUP_SCAN') {
                $customer = $customer ?: (int) $d['CurrentCustomerID'];
                if ($customer <= 0 || !$this->one('SELECT 1 FROM customers WHERE CustomerID = ?', [$customer])) throw new InvalidArgumentException('Select the customer from whom this dispenser was picked up.');
            } else {
                $customer = $customer ?: (int) $d['CurrentCustomerID'];
                if ($customer > 0 && !$this->one('SELECT 1 FROM customers WHERE CustomerID = ?', [$customer])) throw new InvalidArgumentException('Select a valid customer.');
            }
            if ($event === 'DELIVERY_SCAN') {
                $reserved = $this->one("SELECT CustomerID FROM dispenser_borrowing WHERE BorrowingID=?",[$borrow['BorrowingID']]);
                if ((int)$reserved['CustomerID'] !== $customer) throw new DomainException('This dispenser is reserved for a different customer.');
            }
            $this->db->prepare('INSERT INTO dispenser_scan_event (DispenserID, AccID, EventType, CustomerID, PreviousScanEventID, ExpectedPreviousEventType, IsCycleJump, JumpReason) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
                ->execute([$d['DispenserID'], $actor, $event, $customer ?: null, $previous['ScanEventID'] ?? null,
                    $jump ? $steps[$event][2] : null, (int) $jump, $jump ? $reason : null]);
            $scanId = (int) $this->db->lastInsertId();
            $open = $this->one('SELECT DeploymentID FROM dispenser_deployment WHERE DispenserID = ? AND ClosedAt IS NULL ORDER BY DeploymentID DESC LIMIT 1 FOR UPDATE', [$d['DispenserID']]);
            if ($open && $event !== 'DELIVERY_SCAN') {
                if ($event !== 'PICKUP_SCAN' && !$jump) throw new DomainException('An open customer visit requires pickup.');
                $this->db->prepare('UPDATE dispenser_deployment SET ClosedAt = NOW(6), ClosedScanEventID = ?, CloseWasInferred = ? WHERE DeploymentID = ?')
                    ->execute([$scanId, $event === 'PICKUP_SCAN' ? 0 : 1, $open['DeploymentID']]);
            } elseif ($open && $event === 'DELIVERY_SCAN') {
                $this->db->prepare('UPDATE dispenser_deployment SET ClosedAt = NOW(6), ClosedScanEventID = ?, CloseWasInferred = 1 WHERE DeploymentID = ?')
                    ->execute([$scanId, $open['DeploymentID']]);
            }
            if ($event === 'PICKUP_SCAN' && !$open && $jump) {
                // Preserve the customer visit when delivery was not scanned; its start time is unknown.
                $this->db->prepare('INSERT INTO dispenser_deployment (DispenserID, CustomerID, ClosedScanEventID, ClosedAt, DeliveryWasInferred, CloseWasInferred) VALUES (?, ?, ?, NOW(6), 1, 0)')
                    ->execute([$d['DispenserID'], $customer, $scanId]);
            }
            if ($event === 'DELIVERY_SCAN') {
                $this->db->prepare('INSERT INTO dispenser_deployment (DispenserID, CustomerID, DeliveredScanEventID, DeliveredAt) VALUES (?, ?, ?, NOW(6))')
                    ->execute([$d['DispenserID'], $customer, $scanId]);
            }
            $newCustomer = $event === 'RETURN_SCAN' ? null : ($customer ?: null);
            $newActor = in_array($event, ['LOAD_SCAN', 'PICKUP_SCAN'], true) ? $actor : null;
            $this->db->prepare('UPDATE dispensers SET LifecycleStatus = ?, CurrentCustomerID = ?, CurrentAccID = ? WHERE DispenserID = ?')
                ->execute([$steps[$event][1], $newCustomer, $newActor, $d['DispenserID']]);
            if ($event === 'DELIVERY_SCAN') {
                $this->db->prepare("UPDATE dispenser_borrowing SET Status='ACTIVE',DeliveredAt=NOW(6) WHERE BorrowingID=?")->execute([$borrow['BorrowingID']]);
            } elseif ($event === 'PICKUP_SCAN') {
                $this->db->prepare("UPDATE dispenser_borrowing SET Status='PICKED_UP',PickedUpAt=NOW(6) WHERE ActiveDispenserID=? AND Status='ACTIVE'")->execute([$d['DispenserID']]);
            } elseif ($event === 'RETURN_SCAN') {
                $this->db->prepare("UPDATE dispenser_borrowing SET Status='RETURNED',ActiveDispenserID=NULL,PickedUpAt=COALESCE(PickedUpAt,NOW(6)),ReturnedAt=NOW(6) WHERE ActiveDispenserID=?")->execute([$d['DispenserID']]);
            }
            if ($assignment) {
                $status = $event === 'LOAD_SCAN' ? 'OUT_FOR_DELIVERY' : 'DELIVERED';
                $this->db->prepare("UPDATE dispenser_delivery_assignment SET Status=?,OutForDeliveryAt=COALESCE(OutForDeliveryAt,NOW(6)),CompletedAt=CASE WHEN ?='DELIVERED' THEN NOW(6) ELSE NULL END,UpdatedByAccID=?,UpdatedAt=NOW(6) WHERE AssignmentID=?")
                    ->execute([$status,$status,$actor,$assignment['AssignmentID']]);
            }
            $this->db->commit();
            return ['dispenserNumber' => $number, 'lifecycleStatus' => $steps[$event][1], 'isCycleJump' => $jump,
                'scanEventId' => $scanId, 'customerId' => $newCustomer];
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
    }

    public function state(array $input, int $actor): array
    {
        $number = strtoupper(trim((string) ($input['dispenserNumber'] ?? '')));
        $new = strtoupper(trim((string) ($input['physicalState'] ?? '')));
        $note = trim((string) ($input['note'] ?? ''));
        if (!in_array($new, ['HEALTHY', 'DAMAGED', 'INOPERATIVE', 'MISSING'], true) || $note === '') throw new InvalidArgumentException('Select a state and enter a reason.');
        $this->db->beginTransaction();
        try {
            $d = $this->dispenser($number, true);
            if ($d['PhysicalState'] === $new) throw new DomainException('Dispenser already has that state.');
            $this->db->prepare('INSERT INTO dispenser_state_history (DispenserID, PreviousState, NewState, Note, RecordedByAccID) VALUES (?, ?, ?, ?, ?)')
                ->execute([$d['DispenserID'], $d['PhysicalState'], $new, $note, $actor]);
            $this->db->prepare('UPDATE dispensers SET PhysicalState = ? WHERE DispenserID = ?')->execute([$new, $d['DispenserID']]);
            $this->db->commit();
            return ['dispenserNumber' => $number, 'physicalState' => $new];
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
    }

    public function maintenance(array $input, int $actor): array
    {
        $number = strtoupper(trim((string) ($input['dispenserNumber'] ?? '')));
        $external = trim((string) ($input['externalTechnicianName'] ?? ''));
        $worker = (int) ($input['performedByAccId'] ?? 0);
        $note = trim((string) ($input['maintenanceNote'] ?? ''));
        $work = trim((string) ($input['workDone'] ?? ''));
        $customer = (int) ($input['customerId'] ?? 0);
        $location = strtoupper(trim((string) ($input['locationType'] ?? '')));
        $verification = strtoupper(trim((string) ($input['verificationMethod'] ?? 'MANUAL')));
        $verificationNote = trim((string) ($input['verificationNote'] ?? ''));
        $newState = strtoupper(trim((string) ($input['newPhysicalState'] ?? '')));
        $performedAt = trim((string) ($input['performedAt'] ?? ''));
        $locationNote = trim((string) ($input['locationNote'] ?? ''));
        $time = strtotime($performedAt);
        if (($worker > 0) === ($external !== '') || ($verification === 'SCAN' && $note === '') || $work === '' || ($newState !== '' && !in_array($newState, ['HEALTHY', 'DAMAGED', 'INOPERATIVE', 'MISSING'], true)) || !in_array($location, ['CUSTOMER', 'STATION', 'OTHER'], true)
            || ($location === 'OTHER' && $locationNote === '')
            || !in_array($verification, ['SCAN', 'MANUAL'], true) || ($verification === 'MANUAL' && $verificationNote === '')
            || $time === false || $time > time() + 300) throw new InvalidArgumentException('Complete the technician, work, location, date and verification fields.');
        if ($worker > 0 && !$this->one('SELECT 1 FROM accounts WHERE AccID = ?', [$worker])) throw new InvalidArgumentException('Technician account not found.');
        if ($location === 'CUSTOMER' && ($customer <= 0 || !$this->one('SELECT 1 FROM customers WHERE CustomerID = ?', [$customer]))) {
            throw new InvalidArgumentException('Select the customer where maintenance was performed.');
        }
        $this->db->beginTransaction();
        try {
            $d = $this->dispenser($number, true);
            $newState = $newState ?: $d['PhysicalState'];
            $this->db->prepare('INSERT INTO dispenser_maintenance (DispenserID, CustomerID, PerformedByAccID, ExternalTechnicianName, RecordedByAccID, LocationType, LocationNote, MaintenanceNote, WorkDone, PreviousState, NewState, PerformedAt, VerificationMethod, VerificationNote) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
                ->execute([$d['DispenserID'], $location === 'CUSTOMER' ? $customer : null, $worker ?: null, $external ?: null, $actor, $location,
                    $locationNote ?: null, $note, $work, $d['PhysicalState'], $newState, date('Y-m-d H:i:s', $time), $verification,
                    $verificationNote ?: null]);
            $id = (int) $this->db->lastInsertId();
            if ($newState !== $d['PhysicalState']) {
                $this->db->prepare('INSERT INTO dispenser_state_history (DispenserID, PreviousState, NewState, Note, RecordedByAccID) VALUES (?, ?, ?, ?, ?)')
                    ->execute([$d['DispenserID'], $d['PhysicalState'], $newState, 'Maintenance #' . $id . ': ' . $work, $actor]);
                $this->db->prepare('UPDATE dispensers SET PhysicalState = ? WHERE DispenserID = ?')->execute([$newState, $d['DispenserID']]);
            }
            $this->db->commit();
            return ['maintenanceId' => $id, 'dispenserNumber' => $number, 'previousState' => $d['PhysicalState'], 'newState' => $newState];
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        }
    }
}
