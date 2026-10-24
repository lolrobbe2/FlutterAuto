# 1. Forceer het Dart Pub bin-pad in deze sessie om 'not recognized' te voorkomen
$PubBinPath = "C:\Users\robbe\AppData\Local\Pub\Cache\bin"
if ($env:Path -notlike "*$PubBinPath*") {
    $env:Path += ";$PubBinPath"
}

# 2. Zorg dat de doelmap bestaat (absoluut pad)
$OutputDir = "$PSScriptRoot\lib\generated"
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir
}

# 3. Verzamel alle .proto bestanden met een relatief pad vanaf de projectroot (bijv. "oaa/audio/file.proto")
$ProtoFiles = Get-ChildItem -Path ".\oaa" -Filter *.proto -Recurse | ForEach-Object {
    $FormatPath = $_.FullName -replace [regex]::Escape("$PSScriptRoot\"), ""
    $FormatPath -replace "\\", "/"
}

# 4. Voer protoc uit vanuit de projectroot met de hoofdmap (.) als zoekpad
foreach ($File in $ProtoFiles) {
    protoc --proto_path=. --dart_out="$OutputDir" $File
}
