[CmdletBinding()]
param(
    [switch]$SkipDartFix,
    [switch]$SkipFormat,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$repoRoot = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'Save this script in the FlutterAuto repository root before running it.'
}

Set-Location $repoRoot

function Resolve-DartExecutable {
    $dartCommand = Get-Command dart -ErrorAction SilentlyContinue
    if ($null -ne $dartCommand) {
        return $dartCommand.Source
    }

    # Flutter normally bundles the Dart SDK even when dart.exe is not on PATH.
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $flutterCommand) {
        $flutterBin = Split-Path -Parent $flutterCommand.Source
        $bundledDart = Join-Path $flutterBin 'cache\dart-sdk\bin\dart.exe'
        if (Test-Path -LiteralPath $bundledDart) {
            return $bundledDart
        }
    }

    throw 'Could not locate dart.exe. Add Dart or Flutter to PATH and try again.'
}

function Update-ExternalUiTestCleanup {
    $testPath = Join-Path $repoRoot 'headunit_runtime\test\shell\external_application_ui_shell_test.dart'
    if (-not (Test-Path -LiteralPath $testPath)) {
        Write-Host 'UI shell test cleanup: skipped (test file not found).' -ForegroundColor DarkGray
        return 'SKIP'
    }

    $original = [System.IO.File]::ReadAllText($testPath)

    # Idempotency: do not rewrite a test that already resets the override.
    $alreadyResetsOverride = $original -match 'debugDefaultTargetPlatformOverride\s*=\s*null\s*;'
    $updated = $original

    if ($alreadyResetsOverride) {
        # Also clean up a stale saved-value variable if only half the fix was applied.
        $updated = [regex]::Replace(
            $updated,
            '(?m)^[ \t]*late TargetPlatform\? previousPlatform;[ \t]*\r?\n',
            ''
        )
        $updated = [regex]::Replace(
            $updated,
            '(?m)^[ \t]*previousPlatform = debugDefaultTargetPlatformOverride;[ \t]*\r?\n',
            ''
        )
        if ($updated -eq $original) {
            Write-Host 'UI shell test cleanup: already applied.' -ForegroundColor Green
            return 'PASS'
        }
    }
    else {
        # Recognize the original cleanup (or the variant without the old-value restore).
        $teardownPattern = '(?s)tearDown\(\(\) async \{\s*await runtime\.dispose\(\);\s*(?:debugDefaultTargetPlatformOverride\s*=\s*previousPlatform;\s*)?\}\);'
        if ($original -notmatch $teardownPattern) {
            Write-Warning 'UI shell test cleanup was not changed: its tearDown block did not match the expected structure.'
            return 'SKIP'
        }

        $cleanupReplacement = @'
tearDown(() async {
      try {
        await runtime.dispose();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
'@
        $cleanupReplacement = $cleanupReplacement.TrimEnd()
        $updated = [regex]::Replace(
            $original,
            $teardownPattern,
            $cleanupReplacement,
            1
        )

        $updated = [regex]::Replace(
            $updated,
            '(?m)^[ \t]*late TargetPlatform\? previousPlatform;[ \t]*\r?\n',
            ''
        )
        $updated = [regex]::Replace(
            $updated,
            '(?m)^[ \t]*previousPlatform = debugDefaultTargetPlatformOverride;[ \t]*\r?\n',
            ''
        )
    }

    if ($updated -match '\bpreviousPlatform\b') {
        Write-Warning 'UI shell test cleanup was not changed: unexpected previousPlatform references remain.'
        return 'SKIP'
    }

    if ($updated -eq $original) {
        Write-Host 'UI shell test cleanup: already applied.' -ForegroundColor Green
        return 'PASS'
    }

    if (-not $NoBackup) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        Copy-Item -LiteralPath $testPath -Destination "$testPath.$timestamp.bak"
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($testPath, $updated, $utf8NoBom)
    Write-Host 'UI shell test cleanup: patched (backup created unless -NoBackup was used).' -ForegroundColor Yellow
    return 'PASS'

}

$dartExecutable = Resolve-DartExecutable
$knownFixStatus = Update-ExternalUiTestCleanup

$packages = @(
    'headunit_shared',
    'headunit_sdk',
    'headunit_runtime',
    'headunit_web_runtime'
)

$results = @()

foreach ($package in $packages) {
    $packagePath = Join-Path $repoRoot $package
    if (-not (Test-Path -LiteralPath (Join-Path $packagePath 'pubspec.yaml'))) {
        Write-Host "Skipping $package (no pubspec.yaml)" -ForegroundColor DarkGray
        continue
    }

    Write-Host "`n===== $package =====" -ForegroundColor Cyan
    Push-Location $packagePath

    try {
        $content = Get-Content pubspec.yaml -Raw
        $tool = if ($content -match '(?m)^\s*sdk:\s*flutter\s*$') { 'flutter' } else { 'dart' }

        & $tool pub get
        $pubGet = $LASTEXITCODE

        $autoFix = 0
        $format = 0

        if (-not $SkipDartFix) {
            Write-Host "`nApplying supported Dart quick-fixes in $package..." -ForegroundColor Yellow
            & $dartExecutable fix --apply
            $autoFix = $LASTEXITCODE
        } else {
            Write-Host 'Skipping dart fix --apply (-SkipDartFix).' -ForegroundColor DarkGray
        }

        if (-not $SkipFormat) {
            Write-Host "`nFormatting Dart files in $package..." -ForegroundColor Yellow
            & $dartExecutable format .
            $format = $LASTEXITCODE
        } else {
            Write-Host 'Skipping dart format (-SkipFormat).' -ForegroundColor DarkGray
        }

        Write-Host "`nAnalyzing $package..." -ForegroundColor Yellow
        & $tool analyze
        $analyze = $LASTEXITCODE

        if (Test-Path 'test') {
            Write-Host "`nRunning tests in $package..." -ForegroundColor Yellow
            & $tool test
            $test = $LASTEXITCODE
        } else {
            $test = 0
        }

        $results += [PSCustomObject]@{
            Package = $package
            PubGet = if ($pubGet -eq 0) { 'PASS' } else { 'FAIL' }
            AutoFix = if ($SkipDartFix) { 'SKIP' } elseif ($autoFix -eq 0) { 'PASS' } else { 'FAIL' }
            Format = if ($SkipFormat) { 'SKIP' } elseif ($format -eq 0) { 'PASS' } else { 'FAIL' }
            Analyze = if ($analyze -eq 0) { 'PASS' } else { 'FAIL' }
            Tests = if ($test -eq 0) { 'PASS' } else { 'FAIL' }
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host "`n===== HEADUNIT TEST SUMMARY =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "Known UI test cleanup: $knownFixStatus"

$failed = $results | Where-Object {
    $_.PubGet -eq 'FAIL' -or
    $_.AutoFix -eq 'FAIL' -or
    $_.Format -eq 'FAIL' -or
    $_.Analyze -eq 'FAIL' -or
    $_.Tests -eq 'FAIL'
}

if ($failed) {
    Write-Host 'Some checks failed. Review remaining analyzer diagnostics and test output.' -ForegroundColor Red
    exit 1
}

Write-Host 'All Headunit package checks passed!' -ForegroundColor Green
