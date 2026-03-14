param(
    [string]$PythonExe = "python",
    [switch]$IncludeDev
)

$ErrorActionPreference = "Stop"

& $PythonExe -m venv .venv
& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt

if ($IncludeDev) {
    & .\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
}

Write-Host "Environment ready. Activate with: .\\.venv\\Scripts\\Activate.ps1"
if ($IncludeDev) {
    Write-Host "Dev dependencies installed. Run tests with: .\\.venv\\Scripts\\python.exe -m pytest"
}
