param(
    [string]$Flutter = 'flutter',
    [switch]$BuildAndroid
)
$ErrorActionPreference = 'Stop'
$appDirectory = Join-Path $PSScriptRoot '../app'
Push-Location $appDirectory
try {
    foreach ($arguments in @(
        @('--version'),
        @('pub', 'get', '--enforce-lockfile'),
        @('analyze'),
        @('test')
    )) {
        & $Flutter @arguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter check failed: $arguments" }
    }
    if ($BuildAndroid) {
        & $Flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw 'Android debug build failed' }
    }
} finally {
    Pop-Location
}
