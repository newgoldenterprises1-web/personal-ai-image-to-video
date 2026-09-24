param(
  [string]$ComfyUIPath = "$env:USERPROFILE\ComfyUI",
  [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$entry = Join-Path $ComfyUIPath "main.py"

if (-not (Test-Path $entry)) {
  throw "ComfyUI main.py was not found at $ComfyUIPath. Install ComfyUI there or pass -ComfyUIPath <path>."
}

if ($null -eq (Get-Command $Python -ErrorAction SilentlyContinue)) {
  throw "Python executable '$Python' was not found on PATH."
}

Write-Host "Starting ComfyUI on http://127.0.0.1:8188" -ForegroundColor Cyan
Set-Location $ComfyUIPath
& $Python ".\main.py" --listen 127.0.0.1 --port 8188
