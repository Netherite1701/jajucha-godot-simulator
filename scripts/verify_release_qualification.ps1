$ErrorActionPreference = "Stop"
$report = Get-Content "release\qualification.json" -Raw | ConvertFrom-Json
$failed = @($report.gates.PSObject.Properties | Where-Object { -not $_.Value.passed -or [string]::IsNullOrWhiteSpace([string]$_.Value.evidence) })
if ($failed.Count -gt 0) {
    $names = ($failed | ForEach-Object Name) -join ", "
    throw "Stable publication blocked. Unpassed or undocumented gates: $names"
}
Write-Output "Release qualification passed for $($report.target) v$($report.version)."
