param(
    [string]$Flutter = 'flutter',
    [switch]$BuildAndroid,
    [string]$DartDefineFile,
    [string]$GradleUserHome,
    [string]$JavaHome
)
$ErrorActionPreference = 'Stop'
$appDirectory = Join-Path $PSScriptRoot '../app'
$previousGradleHome = $env:GRADLE_USER_HOME
$previousGradleOptions = $env:GRADLE_OPTS
Push-Location $appDirectory
try {
    if ($GradleUserHome) {
        if (-not (Test-Path -LiteralPath $GradleUserHome -PathType Container)) {
            throw 'Gradle user home must be an existing physical directory.'
        }
        $env:GRADLE_USER_HOME = (Resolve-Path -LiteralPath $GradleUserHome).Path
    }
    if ($JavaHome) {
        if (-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe') -PathType Leaf)) {
            throw 'Java home must contain bin/java.exe.'
        }
        $env:GRADLE_OPTS = "$previousGradleOptions `"-Dorg.gradle.java.home=$JavaHome`""
    }
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
        $buildArguments = @('build', 'apk', '--debug')
        if ($DartDefineFile) {
            if (-not (Test-Path -LiteralPath $DartDefineFile -PathType Leaf)) {
                throw 'Dart define file does not exist (path is relative to app/).'
            }
            $buildArguments += "--dart-define-from-file=$DartDefineFile"
        }
        & $Flutter @buildArguments
        if ($LASTEXITCODE -ne 0) { throw 'Android debug build failed' }
    }
} finally {
    $env:GRADLE_USER_HOME = $previousGradleHome
    $env:GRADLE_OPTS = $previousGradleOptions
    Pop-Location
}
