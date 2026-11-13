$packages = @(
    "headunit_shared",
    "headunit_sdk",
    "headunit_runtime",
    "headunit_web_runtime"
)

$results = @()

foreach ($package in $packages) {
    if (-not (Test-Path "$package\pubspec.yaml")) {
        Write-Host "Skipping $package (no pubspec.yaml)" -ForegroundColor DarkGray
        continue
    }

    Write-Host "`n===== $package =====" -ForegroundColor Cyan

    Push-Location $package

    $content = Get-Content pubspec.yaml -Raw
    $tool = if ($content -match '(?m)^\s*sdk:\s*flutter\s*$') {
        "flutter"
    } else {
        "dart"
    }

    & $tool pub get
    $pubGet = $LASTEXITCODE

    & $tool analyze
    $analyze = $LASTEXITCODE

    if (Test-Path "test") {
        & $tool test
        $test = $LASTEXITCODE
    } else {
        $test = 0
    }

    $results += [PSCustomObject]@{
        Package = $package
        PubGet = if ($pubGet -eq 0) { "PASS" } else { "FAIL" }
        Analyze = if ($analyze -eq 0) { "PASS" } else { "FAIL" }
        Tests = if ($test -eq 0) { "PASS" } else { "FAIL" }
    }

    Pop-Location
}

Write-Host "`n===== HEADUNIT TEST SUMMARY =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($results | Where-Object {
    $_.PubGet -eq "FAIL" -or
    $_.Analyze -eq "FAIL" -or
    $_.Tests -eq "FAIL"
}) {
    Write-Host "Some checks failed." -ForegroundColor Red
    exit 1
}

Write-Host "All Headunit package checks passed!" -ForegroundColor Green