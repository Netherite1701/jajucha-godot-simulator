param(
    [string]$OutputDirectory = "build\runtime\python",
    [string]$WorkDirectory = ".cache\cpython-3.12.15"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path ".").Path
$work = Join-Path $root $WorkDirectory
$output = Join-Path $root $OutputDirectory
$archive = Join-Path $work "Python-3.12.15.tar.xz"
$source = Join-Path $work "Python-3.12.15"
$pythonSourceUrl = "https://www.python.org/ftp/python/3.12.15/Python-3.12.15.tar.xz"
$expectedHash = "c2c4321961fab0fb999d66e0cecf521c2ab3994c7992873ea99e306c1094fd5a"

New-Item -ItemType Directory -Force -Path $work | Out-Null
if (Test-Path -LiteralPath $output) {
    $resolvedOutput = (Resolve-Path $output).Path
    if (-not $resolvedOutput.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to clean a runtime path outside the project: $resolvedOutput" }
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
Invoke-WebRequest -Uri $pythonSourceUrl -OutFile $archive
$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) { throw "CPython source SHA-256 mismatch: $actualHash" }
if (Test-Path -LiteralPath $source) { Remove-Item -LiteralPath $source -Recurse -Force }
tar -xf $archive -C $work
if ($LASTEXITCODE -ne 0) { throw "Could not extract the CPython source archive." }

$build = Join-Path $source "PCbuild\build.bat"
& $build -p x64 -c Release -e
if ($LASTEXITCODE -ne 0) { throw "CPython source build failed with exit code $LASTEXITCODE." }

# CPython's own layout tool turns the Release build into a relocatable runtime.
$layout = Join-Path $source "PC\layout"
$buildDirectory = Join-Path $source "PCbuild\amd64"
python $layout --copy $output --source $source --build $buildDirectory --arch amd64 --preset-embed --include-pip
if ($LASTEXITCODE -ne 0) { throw "CPython runtime layout failed with exit code $LASTEXITCODE." }

$pth = Join-Path $output "python312._pth"
$lines = Get-Content -LiteralPath $pth
if ($lines -notcontains "Lib/site-packages") { $lines += "Lib/site-packages" }
if ($lines -notcontains "import site") { $lines += "import site" }
Set-Content -LiteralPath $pth -Value $lines -Encoding ascii
New-Item -ItemType Directory -Force -Path (Join-Path $output "Lib\site-packages") | Out-Null

$runtimePython = Join-Path $output "python.exe"
& $runtimePython -m pip install --disable-pip-version-check --require-hashes --only-binary=:all: --target (Join-Path $output "Lib\site-packages") -r (Join-Path $root "requirements.lock")
if ($LASTEXITCODE -ne 0) { throw "Installing the hashed Python requirements failed with exit code $LASTEXITCODE." }
Copy-Item -LiteralPath (Join-Path $root "python_bridge\jchm.py") -Destination (Join-Path $output "Lib\site-packages\jchm.py") -Force
& $runtimePython -c "import sys, cv2, ipykernel, IPython, jchm, jupyter_client, nbformat, numpy; assert sys.version_info[:3] == (3, 12, 15), sys.version; print('RUNTIME_OK', sys.version, numpy.__version__, cv2.__version__, jchm.__file__)"
if ($LASTEXITCODE -ne 0) { throw "The bundled Python runtime smoke test failed." }
& $runtimePython (Join-Path $root "scripts\write_runtime_licenses.py") (Join-Path $output "licenses")
if ($LASTEXITCODE -ne 0) { throw "Could not write Python dependency notices." }
Write-Output "CPython 3.12.15 runtime ready: $output"
