$ErrorActionPreference = 'Stop'

$runtimeRoot = (Get-Location).Path
$surfacePath = Join-Path $runtimeRoot 'lib\src\media\presentation\src\remote_video_surface.dart'
$videoDecoderPath = Join-Path $runtimeRoot 'lib\src\media\presentation\src\video_decoder.dart'
$ffmpegDecoderPath = Join-Path $runtimeRoot 'lib\src\media\presentation\src\ffmpeg_video_decoder.dart'
$parserTestPath = Join-Path $runtimeRoot 'example\test\media_demo\h264_annex_b_parser_test.dart'

if (-not (Test-Path $surfacePath)) {
    throw 'Run this script from the headunit_runtime directory.'
}
foreach ($path in @($videoDecoderPath, $ffmpegDecoderPath, $parserTestPath)) {
    if (-not (Test-Path $path)) {
        throw "Required file not found: $path"
    }
}

$surface = [System.IO.File]::ReadAllText($surfacePath)
$videoDecoder = [System.IO.File]::ReadAllText($videoDecoderPath)
$ffmpegDecoder = [System.IO.File]::ReadAllText($ffmpegDecoderPath)
$parserTest = [System.IO.File]::ReadAllText($parserTestPath)

# Locate an existing optional-start interface before adding one. It belongs in
# video_decoder.dart; avoid duplicating it if an earlier local edit added it.
$startableDeclarationExists = $false
$presentationRoot = Join-Path $runtimeRoot 'lib\src\media\presentation'
foreach ($file in (Get-ChildItem -Path $presentationRoot -Recurse -Filter '*.dart' -File)) {
    $source = [System.IO.File]::ReadAllText($file.FullName)
    if ($source -match '(?m)^abstract\s+interface\s+class\s+StartableVideoDecoder\b') {
        $startableDeclarationExists = $true
        break
    }
}

if (-not $startableDeclarationExists) {
    $videoDecoder = $videoDecoder.TrimEnd() + @'


/// Optional lifecycle capability for decoders that must start only after
/// their Flutter output surface has been mounted.
abstract interface class StartableVideoDecoder {
  Future<void> start();
}
'@
}

# FfmpegVideoDecoder exposes start(), so declare the capability explicitly.
if ($ffmpegDecoder -notmatch 'class\s+FfmpegVideoDecoder\s+implements\s+VideoDecoder\s*,\s*StartableVideoDecoder') {
    $classMatch = [regex]::Match(
        $ffmpegDecoder,
        'class\s+FfmpegVideoDecoder\s+implements\s+VideoDecoder\s*\{'
    )
    if (-not $classMatch.Success) {
        throw 'Unexpected FfmpegVideoDecoder declaration. No files were changed.'
    }
    $ffmpegDecoder = $ffmpegDecoder.Substring(0, $classMatch.Index) +
        'class FfmpegVideoDecoder implements VideoDecoder, StartableVideoDecoder {' +
        $ffmpegDecoder.Substring($classMatch.Index + $classMatch.Length)
}

# Replace the invalid base-interface call with an optional-capability check.
# Waiting for endOfFrame ensures setState has mounted the FFplay surface before
# FFplay starts attempting to render into it.
$startCall = [regex]::Match(
    $surface,
    '(?m)^(?<indent>[ \t]*)await\s+decoder\.start\(\);[ \t]*$'
)
if ($startCall.Success) {
    $indent = $startCall.Groups['indent'].Value
    $newline = "`r`n"
    $replacementLines = @(
        "${indent}if (decoder is StartableVideoDecoder) {",
        "${indent}  await WidgetsBinding.instance.endOfFrame;",
        "${indent}  if (!_isCurrent(generation) || !identical(_decoder, decoder)) {",
        "${indent}    subscription?.cancel();",
        "${indent}    await decoder.dispose();",
        "${indent}    return;",
        "${indent}  }",
        "${indent}  await decoder.start();",
        "${indent}}"
    )
    $replacement = $replacementLines -join $newline
    $surface = $surface.Substring(0, $startCall.Index) +
        $replacement +
        $surface.Substring($startCall.Index + $startCall.Length)
} elseif ($surface -notmatch 'decoder\s+is\s+StartableVideoDecoder') {
    throw 'Could not find decoder.start() in remote_video_surface.dart. No files were changed.'
}

# rootBundle.load() requires ServicesBinding even in a non-widget test.
if ($parserTest -notmatch 'TestWidgetsFlutterBinding\.ensureInitialized\(\)') {
    $mainMatch = [regex]::Match($parserTest, '(?m)^void\s+main\(\)\s*\{')
    if (-not $mainMatch.Success) {
        throw 'Could not locate main() in the H.264 parser test. No files were changed.'
    }
    $mainReplacement = "void main() {`r`n  TestWidgetsFlutterBinding.ensureInitialized();"
    $parserTest = $parserTest.Substring(0, $mainMatch.Index) +
        $mainReplacement +
        $parserTest.Substring($mainMatch.Index + $mainMatch.Length)
}

$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($videoDecoderPath, $videoDecoder, $encoding)
[System.IO.File]::WriteAllText($ffmpegDecoderPath, $ffmpegDecoder, $encoding)
[System.IO.File]::WriteAllText($surfacePath, $surface, $encoding)
[System.IO.File]::WriteAllText($parserTestPath, $parserTest, $encoding)

Write-Host 'FFmpeg demo lifecycle and asset-test fixes applied.' -ForegroundColor Green
Write-Host 'Changed:'
Write-Host '  lib/src/media/presentation/src/video_decoder.dart'
Write-Host '  lib/src/media/presentation/src/ffmpeg_video_decoder.dart'
Write-Host '  lib/src/media/presentation/src/remote_video_surface.dart'
Write-Host '  example/test/media_demo/h264_annex_b_parser_test.dart'
