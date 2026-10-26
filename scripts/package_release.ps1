param(
    [string]$GodotExecutable = ".cache\godot-exporter\Godot_v4.7.2-stable_win64_console.exe",
    [string]$TemplateExecutable = "export_templates\windows_release_x86_64.exe",
    [string]$OutputRoot = "build\release-candidate"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path ".").Path
$godot = (Resolve-Path $GodotExecutable).Path
$template = (Resolve-Path $TemplateExecutable).Path
$outputRootPath = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $root $OutputRoot)) }
New-Item -ItemType Directory -Force -Path $outputRootPath | Out-Null
$stage = Join-Path $outputRootPath "package"
$launcherOutput = Join-Path $outputRootPath "launcher"
$export = Join-Path $root "build\godot\JajuchaGodotSimulatorApp.exe"
$runtime = Join-Path $root "build\runtime\python"
$required = @((Join-Path $runtime "python.exe"), (Join-Path $root "launcher\packages.lock.json"))
foreach ($path in $required) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required release input is missing: $path" } }

$originalPreset = Get-Content "export_presets.cfg" -Raw
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$originalTemp = $env:TEMP
$originalTmp = $env:TMP
$godotUserRoot = Join-Path $root ".cache\godot-export-user"
$godotTemp = Join-Path $godotUserRoot "Temp"
New-Item -ItemType Directory -Force -Path (Join-Path $godotUserRoot "Roaming"), (Join-Path $godotUserRoot "Local"), $godotTemp | Out-Null
$env:APPDATA = Join-Path $godotUserRoot "Roaming"
$env:LOCALAPPDATA = Join-Path $godotUserRoot "Local"
$env:TEMP = $godotTemp
$env:TMP = $godotTemp
$templatePreset = $originalPreset.Replace('custom_template/release=""', 'custom_template/release="' + $template.Replace('\', '/') + '"')
Set-Content -LiteralPath "export_presets.cfg" -Value $templatePreset -NoNewline
try {
    New-Item -ItemType Directory -Force -Path (Split-Path $export -Parent) | Out-Null
    & (Join-Path $runtime "python.exe") scripts\create_starter_notebooks.py
    if ($LASTEXITCODE -ne 0) { throw "Starter notebook generation failed with exit code $LASTEXITCODE." }
    & $godot --headless --path . --script res://scripts/build_editor_assets.gd
    if ($LASTEXITCODE -ne 0) { throw "GridMap/MeshLibrary generation failed with exit code $LASTEXITCODE." }
    if (Test-Path -LiteralPath $export) {
        $resolvedExport = (Resolve-Path $export).Path
        $expectedExportRoot = [IO.Path]::GetFullPath((Join-Path $root "build\godot")) + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedExport.StartsWith($expectedExportRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove an export outside the generated build directory: $resolvedExport" }
        Remove-Item -LiteralPath $resolvedExport -Force
    }
    & $godot --headless --path . --export-release "Windows Desktop" $export
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed with exit code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath $export -PathType Leaf)) { throw "Godot reported success but did not produce the export: $export" }
} finally {
    Set-Content -LiteralPath "export_presets.cfg" -Value $originalPreset -NoNewline
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:TEMP = $originalTemp
    $env:TMP = $originalTmp
}

if (Test-Path -LiteralPath $stage) {
    $resolvedStage = (Resolve-Path $stage).Path
    if (-not $resolvedStage.StartsWith($outputRootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to clean an output path outside the selected output root: $resolvedStage" }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath $export -Destination $stage
$bridgeOutput = Join-Path $stage "python_bridge"
New-Item -ItemType Directory -Force -Path $bridgeOutput | Out-Null
foreach ($bridgeFile in @("notebook_host.py", "jchm.py", "run_python_controller.py", "user_supplied_controller.py", "verified_lap_controller.py")) {
    Copy-Item -LiteralPath (Join-Path $root "python_bridge\$bridgeFile") -Destination $bridgeOutput
}
Copy-Item -LiteralPath $runtime -Destination (Join-Path $stage "python") -Recurse
Copy-Item -LiteralPath (Join-Path $root "notebooks") -Destination $stage -Recurse
Copy-Item -LiteralPath (Join-Path $root "LICENSE") -Destination $stage
Copy-Item -LiteralPath (Join-Path $root "THIRD_PARTY_NOTICES.md") -Destination $stage
Copy-Item -LiteralPath (Join-Path $runtime "licenses") -Destination (Join-Path $stage "licenses") -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $stage "docs") | Out-Null
Copy-Item -LiteralPath (Join-Path $root "docs\INSTALLATION.md") -Destination (Join-Path $stage "docs")

dotnet restore launcher\JajuchaLauncher.csproj -r win-x64 --locked-mode -p:NuGetAudit=false
if ($LASTEXITCODE -ne 0) { throw "Locked launcher restore failed." }
dotnet publish launcher\JajuchaLauncher.csproj -c Release -r win-x64 --self-contained true --no-restore -p:PublishSingleFile=true -o $launcherOutput
if ($LASTEXITCODE -ne 0) { throw "Self-contained launcher publish failed." }
Copy-Item -LiteralPath (Join-Path $launcherOutput "JajuchaGodotSimulator.exe") -Destination $stage

dotnet tool restore --ignore-failed-sources
if ($LASTEXITCODE -ne 0) { throw "Pinned Velopack CLI restore failed." }
$dist = Join-Path $outputRootPath "dist"
if (Test-Path -LiteralPath $dist) {
    $resolvedDist = (Resolve-Path $dist).Path
    if (-not $resolvedDist.StartsWith($outputRootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to clean an output path outside the selected output root: $resolvedDist" }
    Remove-Item -LiteralPath $resolvedDist -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$originalPackTemp = $env:TEMP
$originalPackTmp = $env:TMP
$packTemp = Join-Path $outputRootPath "temp"
New-Item -ItemType Directory -Force -Path $packTemp | Out-Null
try {
    $env:TEMP = $packTemp
    $env:TMP = $packTemp
    dotnet tool run vpk pack --packId "Netherite1701.JajuchaGodotSimulator" --packVersion "0.1.0" --packTitle "Jajucha Godot Simulator" --packDir $stage --mainExe "JajuchaGodotSimulator.exe" --runtime "win-x64" --outputDir $dist
    $packageExitCode = $LASTEXITCODE
} finally {
    $env:TEMP = $originalPackTemp
    $env:TMP = $originalPackTmp
}
if ($packageExitCode -ne 0) { throw "Velopack package creation failed with exit code $packageExitCode." }
$setup = Get-ChildItem -LiteralPath $dist -Filter "*-Setup.exe" | Select-Object -First 1
if ($null -eq $setup) { throw "Velopack did not produce a Windows Setup.exe." }
$namedSetup = Join-Path $dist "JajuchaGodotSimulator-win-x64-Setup.exe"
if (-not [string]::Equals($setup.FullName, $namedSetup, [StringComparison]::OrdinalIgnoreCase)) { Copy-Item -LiteralPath $setup.FullName -Destination $namedSetup -Force }
$selfTestStarted = [DateTime]::UtcNow
$stagedLauncher = Join-Path $stage "JajuchaGodotSimulator.exe"
$originalJajuchaDataDir = $env:JAJUCHA_DATA_DIR
$selfTestDataRoot = Join-Path $outputRootPath "self-test-data"
New-Item -ItemType Directory -Force -Path $selfTestDataRoot | Out-Null
$env:JAJUCHA_DATA_DIR = $selfTestDataRoot
$selfTestStartInfo = [Diagnostics.ProcessStartInfo]::new($stagedLauncher)
$selfTestStartInfo.WorkingDirectory = $stage
$selfTestStartInfo.UseShellExecute = $false
$selfTestStartInfo.Arguments = "--self-test"
$selfTestProcess = [Diagnostics.Process]::Start($selfTestStartInfo)
if ($null -eq $selfTestProcess) { throw "Could not start the packaged structural self-test." }
$selfTestProcess.WaitForExit()
$env:JAJUCHA_DATA_DIR = $originalJajuchaDataDir
if ($selfTestProcess.ExitCode -ne 0) { throw "Packaged structural self-test failed with exit code $($selfTestProcess.ExitCode)." }
$selfTestReport = Join-Path $selfTestDataRoot "evidence\self-test.json"
if (-not (Test-Path -LiteralPath $selfTestReport -PathType Leaf)) { throw "Packaged structural self-test did not write its evidence: $selfTestReport" }
$selfTestFile = Get-Item -LiteralPath $selfTestReport
if ($selfTestFile.LastWriteTimeUtc -lt $selfTestStarted.AddSeconds(-1)) { throw "Packaged structural self-test evidence is stale: $selfTestReport" }
$selfTestResult = Get-Content -LiteralPath $selfTestReport -Raw | ConvertFrom-Json
if (-not $selfTestResult.passed) { throw "Packaged structural self-test reported failure." }
Copy-Item -LiteralPath $selfTestReport -Destination (Join-Path $dist "VERIFICATION_SELF_TEST.json") -Force
Copy-Item -LiteralPath (Join-Path $root "docs\INSTALLATION.md") -Destination $dist
Copy-Item -LiteralPath (Join-Path $root "docs\RELEASE_NOTES_0.1.0.md") -Destination $dist
Copy-Item -LiteralPath (Join-Path $root "docs\LAP_VERIFICATION.md") -Destination $dist
Copy-Item -LiteralPath (Join-Path $root "release\VERIFICATION_REPORT.md") -Destination $dist
$distRelease = Join-Path $dist "release"
New-Item -ItemType Directory -Force -Path $distRelease | Out-Null
Copy-Item -LiteralPath (Join-Path $root "release\qualification.json") -Destination $distRelease -Force
Copy-Item -LiteralPath (Join-Path $root "release\evidence") -Destination $distRelease -Recurse -Force
$checksumFile = Join-Path $dist "SHA256SUMS.txt"
Get-ChildItem -LiteralPath $dist -File -Recurse | Where-Object FullName -ne $checksumFile | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    $relative = $_.FullName.Substring($dist.Length + 1).Replace("\", "/")
    "$hash  $relative"
} | Set-Content -LiteralPath $checksumFile -Encoding ascii
Write-Output "Release candidate staged in $dist"
