$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$server = Join-Path $repoRoot "server"

if ($null -eq (Get-Command node -ErrorAction SilentlyContinue)) {
  throw "Node.js is not installed or not on PATH."
}

$nodeVersion = (& node --version).TrimStart("v")
if ([version]$nodeVersion -lt [version]"20.0.0") {
  throw "Node.js 20+ is required. Detected $nodeVersion."
}

Set-Location $server
if (-not (Test-Path "node_modules")) {
  Write-Host "Installing backend dependencies..."
  npm install
}

if (-not (Test-Path ".env")) {
  Copy-Item ".env.example" ".env"
  Write-Host "Created server/.env from .env.example."
}

Write-Host "Starting local backend on http://127.0.0.1:8787" -ForegroundColor Cyan
npm start
