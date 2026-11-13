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

function Save-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    if (-not $NoBackup) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        Copy-Item -LiteralPath $Path -Destination "$Path.$timestamp.bak"
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Update-ExternalUiTestCleanup {
    $testPath = Join-Path $repoRoot 'headunit_runtime\test\shell\external_application_ui_shell_test.dart'
    if (-not (Test-Path -LiteralPath $testPath)) {
        Write-Host 'UI shell test cleanup: skipped (test file not found).' -ForegroundColor DarkGray
        return 'SKIP'
    }

    $original = [System.IO.File]::ReadAllText($testPath)
    $teardownPattern = '(?ms)^[ \t]*tearDown\(\(\) async \{\r?\n.*?^[ \t]*\}\);'
    $teardownMatches = [regex]::Matches($original, $teardownPattern)

    if ($teardownMatches.Count -ne 1) {
        Write-Warning "UI shell test cleanup was not changed: expected one tearDown block, found $($teardownMatches.Count)."
        return 'SKIP'
    }

    $teardown = $teardownMatches[0].Value
    $requiredStatements = @(
        'debugPrint = binding.debugPrintOverride;',
        'debugDefaultTargetPlatformOverride = null;',
        'debugDoublePrecision = null;',
        'debugBrightnessOverride = null;'
    )
    $alreadyPatched = $true
    foreach ($statement in $requiredStatements) {
        if (-not $teardown.Contains($statement)) {
            $alreadyPatched = $false
            break
        }
    }

    if ($alreadyPatched) {
        Write-Host 'UI shell test cleanup: already applied (all foundation debug globals reset).' -ForegroundColor Green
        return 'PASS'
    }

    $replacement = @'
    tearDown(() async {
      try {
        await runtime.dispose();
      } finally {
        // Restore the test binding's debugPrint hook and clear all foundation
        // overrides checked by debugAssertAllFoundationVarsUnset().
        final TestWidgetsFlutterBinding binding =
            TestWidgetsFlutterBinding.ensureInitialized();
        debugPrint = binding.debugPrintOverride;
        debugDefaultTargetPlatformOverride = null;
        debugDoublePrecision = null;
        debugBrightnessOverride = null;
      }
    });
'@
    $replacement = $replacement.TrimEnd()
    $updated = [regex]::Replace($original, $teardownPattern, $replacement, 1)

    if ($updated -eq $original) {
        Write-Warning 'UI shell test cleanup was not changed.'
        return 'SKIP'
    }

    Save-TextFile -Path $testPath -Content $updated
    Write-Host 'UI shell test cleanup: patched (backup created unless -NoBackup was used).' -ForegroundColor Yellow
    return 'PASS'
}

function Invoke-DartFormatInBatches {
    param(
        [Parameter(Mandatory = $true)][string]$DartExecutable,
        [Parameter(Mandatory = $true)][string[]]$Files,
        [int]$MaximumArgumentCharacters = 8000,
        [int]$MaximumFilesPerBatch = 40
    )

    # Windows limits the complete process command line to about 32K characters.
    # Keep each invocation comfortably below that limit, including executable
    # and PowerShell quoting overhead. A file list is therefore split into
    # conservative batches rather than passed to dart format in one huge call.
    $batch = New-Object 'System.Collections.Generic.List[string]'
    $batchLength = 0
    $allBatchesPassed = $true

    foreach ($file in $Files) {
        $argumentLength = $file.Length + 4 # Allow for quoting and a separator.

        if ($batch.Count -gt 0 -and (
            ($batchLength + $argumentLength) -gt $MaximumArgumentCharacters -or
            $batch.Count -ge $MaximumFilesPerBatch
        )) {
            $batchFiles = $batch.ToArray()
            & $DartExecutable format @batchFiles
            if ($LASTEXITCODE -ne 0) {
                $allBatchesPassed = $false
            }
            $batch.Clear()
            $batchLength = 0
        }

        $batch.Add($file)
        $batchLength += $argumentLength
    }

    if ($batch.Count -gt 0) {
        $batchFiles = $batch.ToArray()
        & $DartExecutable format @batchFiles
        if ($LASTEXITCODE -ne 0) {
            $allBatchesPassed = $false
        }
    }

    if ($allBatchesPassed) { return 0 }
    return 1
}

function Get-DartSourceFiles {
    param([Parameter(Mandatory = $true)][string]$Directory)

    # Walk source trees but prune generated/cache directories before descending.
    $files = Get-ChildItem -LiteralPath $Directory -File -Filter '*.dart' -ErrorAction Stop
    foreach ($file in $files) {
        $file.FullName
    }

    $excludedDirectories = @('.dart_tool', '.git', 'build', 'coverage', 'node_modules', '.idea', 'example', '.plugin_symlinks', 'ephemeral')
    $subdirectories = Get-ChildItem -LiteralPath $Directory -Directory -ErrorAction Stop
    foreach ($subdirectory in $subdirectories) {
        # Do not descend into nested examples, generated plugin links, or any
        # directory junction/symlink. These may point outside this package.
        if ($excludedDirectories -contains $subdirectory.Name) {
            continue
        }
        if (($subdirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            continue
        }
        Get-DartSourceFiles -Directory $subdirectory.FullName
    }
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

        Write-Host "`nResolving dependencies in $package..." -ForegroundColor Yellow
        & $tool pub get
        $pubGet = $LASTEXITCODE

        $autoFixStatus = 'SKIP'
        if (-not $SkipDartFix) {
            Write-Host "`nApplying supported Dart quick-fixes in $package..." -ForegroundColor Yellow
            & $dartExecutable fix --apply
            $autoFixStatus = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }
        } else {
            Write-Host 'Skipping dart fix --apply (-SkipDartFix).' -ForegroundColor DarkGray
        }

        $formatStatus = 'SKIP'
        if (-not $SkipFormat) {
            Write-Host "`nFormatting project Dart source files in $package (excluding example, generated/cache and symlink directories)..." -ForegroundColor Yellow
            # Keep formatting scoped to this package's own source and tests.
            # The nested example is a separate Flutter project and may contain
            # plugin symlinks to third-party packages with their own lint config.
            $formatRoots = @('lib', 'test', 'bin', 'tool', 'integration_test', 'test_driver', 'benchmark', 'web')
            $formatFiles = @()
            foreach ($formatRoot in $formatRoots) {
                if (Test-Path -LiteralPath $formatRoot -PathType Container) {
                    $formatFiles += @(Get-DartSourceFiles -Directory (Resolve-Path -LiteralPath $formatRoot).Path)
                }
            }

            if ($formatFiles.Count -gt 0) {
                Write-Host "Formatting $($formatFiles.Count) Dart files in bounded batches..." -ForegroundColor DarkGray
                $formatExitCode = Invoke-DartFormatInBatches `
                    -DartExecutable $dartExecutable `
                    -Files $formatFiles
                $formatStatus = if ($formatExitCode -eq 0) { 'PASS' } else { 'FAIL' }
            } else {
                Write-Host 'No Dart source files found in the configured source directories.' -ForegroundColor DarkGray
                $formatStatus = 'PASS'
            }
        } else {
            Write-Host 'Skipping dart format (-SkipFormat).' -ForegroundColor DarkGray
        }

        Write-Host "`nAnalyzing $package (excluding example)..." -ForegroundColor Yellow
        $analysisRoots = @('lib', 'test', 'bin', 'tool', 'integration_test', 'test_driver', 'benchmark', 'web')
        $analysisPaths = @($analysisRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
        $analyze = 0
        if ($analysisPaths.Count -gt 0) {
            # Analyze each source root separately because `flutter analyze`
            # accepts a single target path, while `dart analyze` accepts lists.
            foreach ($analysisPath in $analysisPaths) {
                Write-Host "Analyzing $package\$analysisPath..." -ForegroundColor DarkGray
                & $tool analyze $analysisPath
                if ($LASTEXITCODE -ne 0) {
                    $analyze = $LASTEXITCODE
                }
            }
        } else {
            & $tool analyze
            $analyze = $LASTEXITCODE
        }

        if (Test-Path -LiteralPath 'test' -PathType Container) {
            Write-Host "`nRunning tests in $package..." -ForegroundColor Yellow
            & $tool test
            $test = $LASTEXITCODE
        } else {
            $test = 0
        }

        $results += [PSCustomObject]@{
            Package = $package
            PubGet = if ($pubGet -eq 0) { 'PASS' } else { 'FAIL' }
            AutoFix = $autoFixStatus
            Format = $formatStatus
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

if ($failed -or $knownFixStatus -eq 'SKIP') {
    Write-Host 'Some checks failed or a known fix could not be applied. Review the output above.' -ForegroundColor Red
    exit 1
}

Write-Host 'All Headunit package checks passed!' -ForegroundColor Green
