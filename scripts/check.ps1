param([switch]$BuildApk)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    dart format --output=none --set-exit-if-changed lib test integration_test test_driver
    if ($LASTEXITCODE -ne 0) { throw 'Dart formatting check failed.' }
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    if ($BuildApk) {
        flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw 'Android debug build failed.' }
    }
} finally {
    Pop-Location
}
