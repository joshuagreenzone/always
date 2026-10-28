<?php

function isRegistrationBottleNumber(string $number, string $prefix): bool
{
    // Legacy A codes can be registered under either selected bottle type.
    if (preg_match('/\AA-[0-9]{4}\z/', $number) === 1) return true;
    $prefix = trim($prefix);
    return $prefix !== '' && preg_match('/\A' . preg_quote($prefix, '/') . '-[0-9]{4}\z/', $number) === 1;
}
