<#
    build-and-verify.ps1

    Compiles Pantheon: Champions and regenerates + validates
    pantheon_champions-common.toml against the real ModConfigSpec.

    Thin wrapper over Gradle. Earlier this script resolved the dependency jars
    itself with a hand-written list, and that list drifted four separate times
    (a -sources.jar matched a pattern; then IEventBus, slf4j, and Dist were each
    missing in turn), every one surfacing as a confusing compile error. Gradle
    already resolves the classpath, so the work now lives in the `verifyConfig`
    JavaExec task in build.gradle.

    Usage:
      powershell -NoProfile -ExecutionPolicy Bypass -File Tools\build-and-verify.ps1

    Exit code: 0 = compiled and TOML validated, 1 = something failed.
#>
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Continue"
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue

$gradlew = Join-Path $ProjectRoot "gradlew.bat"
if (-not (Test-Path $gradlew)) {
    Write-Output ("FAIL: gradlew.bat not found at " + $gradlew)
    exit 1
}

Push-Location $ProjectRoot
try {
    Write-Output "=== gradlew build (compiles main + test) ==="
    & $gradlew build --console=plain 2>&1 | ForEach-Object { Write-Output ("  " + $_) }
    $buildExit = $LASTEXITCODE

    Write-Output ""
    Write-Output "=== gradlew verifyConfig (regenerate + validate TOML) ==="
    & $gradlew verifyConfig --console=plain 2>&1 | ForEach-Object { Write-Output ("  " + $_) }
    $verifyExit = $LASTEXITCODE
} finally {
    Pop-Location
}

# The harness writes to the project-root copy; mirror it into resources so the
# packaged mod ships the same file that was just validated.
$generated = Join-Path $ProjectRoot "pantheon_champions-common.toml"
$resourceCopy = Join-Path $ProjectRoot "src\main\resources\pantheon_champions-common.toml"
if ((Test-Path $generated) -and $verifyExit -eq 0) {
    Copy-Item -Path $generated -Destination $resourceCopy -Force
    Write-Output ""
    Write-Output "  synced -> src\main\resources\pantheon_champions-common.toml"
}

Write-Output ""
if ($buildExit -eq 0 -and $verifyExit -eq 0) {
    Write-Output "RESULT: PASS - compiled and generated TOML validates against the spec"
    exit 0
} else {
    Write-Output ("RESULT: FAIL - build exit {0}, verify exit {1}" -f $buildExit, $verifyExit)
    exit 1
}
