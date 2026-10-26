$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installationRoot = (Get-Content -LiteralPath (Join-Path $projectRoot "GODOT_PATH.md") -Raw).Trim()
$godotExecutable = Join-Path $installationRoot "Godot_v4.7.2-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godotExecutable)) {
    throw "Godot 4.7.2 was not found at $godotExecutable"
}
& $godotExecutable --path $projectRoot
