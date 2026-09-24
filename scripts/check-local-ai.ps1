param(
  [string]$ComfyUIPath = "$env:USERPROFILE\ComfyUI",
  [string]$ComfyUIUrl = "http://127.0.0.1:8188"
)

$ErrorActionPreference = "SilentlyContinue"

function Test-Command([string]$Name) {
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  if ($Ok) {
    Write-Host "[OK]   $Name - $Detail" -ForegroundColor Green
  } else {
    Write-Host "[FAIL] $Name - $Detail" -ForegroundColor Red
    $script:Failed = $true
  }
}

Write-Host "Personal AI Image -> Video Studio | Local AI readiness" -ForegroundColor Cyan
Write-Host ""

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$workflow = Join-Path $repoRoot "server\workflows\image-to-video.json"
$checkpoint = Join-Path $ComfyUIPath "models\checkpoints\ltx-video-2b-v0.9.5.safetensors"
$textEncoder = Join-Path $ComfyUIPath "models\text_encoders\t5xxl_fp16.safetensors"

Check "Node.js" (Test-Command "node") "Node 20+ is required."
if (Test-Command "node") {
  $nodeVersion = (& node --version)
  Check "Node version" ([version]($nodeVersion.TrimStart("v")) -ge [version]"20.0.0") "$nodeVersion"
}

Check "FFmpeg" (Test-Command "ffmpeg") "FFmpeg must be available on PATH."
Check "Workflow file" (Test-Path $workflow) $workflow
Check "ComfyUI folder" (Test-Path $ComfyUIPath) $ComfyUIPath
Check "LTX checkpoint" (Test-Path $checkpoint) $checkpoint
Check "T5/CLIP text encoder" (Test-Path $textEncoder) $textEncoder

if (Test-Path $workflow) {
  try {
    $json = Get-Content $workflow -Raw | ConvertFrom-Json
    $types = @($json.PSObject.Properties.Value | ForEach-Object { $_.class_type })
    $required = @(
      "CLIPLoader",
      "CheckpointLoaderSimple",
      "CLIPTextEncode",
      "LTXVImgToVideo",
      "LTXVConditioning",
      "LTXVScheduler",
      "SamplerCustom",
      "VAEDecode",
      "CreateVideo",
      "SaveVideo"
    )
    $missing = $required | Where-Object { $_ -notin $types }
    Check "Workflow graph" ($missing.Count -eq 0) ($(if ($missing.Count -eq 0) { "All required LTXV nodes present." } else { "Missing: $($missing -join ', ')" }))
  } catch {
    Check "Workflow JSON" $false $_.Exception.Message
  }
}

try {
  $health = Invoke-RestMethod "$ComfyUIUrl/system_stats" -TimeoutSec 3
  Check "ComfyUI server" $true "$ComfyUIUrl is responding."
  try {
    $info = Invoke-RestMethod "$ComfyUIUrl/object_info/LTXVImgToVideo" -TimeoutSec 5
    Check "LTXV nodes" ($null -ne $info.LTXVImgToVideo) "LTXVImgToVideo is registered."
  } catch {
    Check "LTXV nodes" $false "LTXVImgToVideo is not registered. Update/install a current ComfyUI build."
  }
} catch {
  Check "ComfyUI server" $false "Start ComfyUI at $ComfyUIUrl."
}

Write-Host ""
if ($script:Failed) {
  Write-Host "Local AI is NOT ready yet." -ForegroundColor Yellow
  Write-Host "Install/fix the failed items, then run this script again."
  exit 1
}

Write-Host "Local AI prerequisites look ready. Next test: run the Node backend, connect Android over USB, and generate one 2-second scene." -ForegroundColor Green
exit 0
