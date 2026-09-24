param(
  [string]$ComfyUIPath = "$env:USERPROFILE\ComfyUI"
)

$ErrorActionPreference = "Stop"

$checkpointDir = Join-Path $ComfyUIPath "models\checkpoints"
$textEncoderDir = Join-Path $ComfyUIPath "models\text_encoders"

$checkpoint = Join-Path $checkpointDir "ltx-video-2b-v0.9.5.safetensors"
$textEncoder = Join-Path $textEncoderDir "t5xxl_fp16.safetensors"
$checkpointLicense = Join-Path $checkpointDir "ltx-video-2b-v0.9.5.license.txt"

$checkpointUrl = "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.5.safetensors?download=true"
$textEncoderUrl = "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors?download=true"
$licenseUrl = "https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.5.license.txt?download=true"

if (-not (Test-Path $ComfyUIPath)) {
  throw "ComfyUI folder was not found at $ComfyUIPath. Install ComfyUI first or pass -ComfyUIPath <path>."
}

New-Item -ItemType Directory -Force -Path $checkpointDir | Out-Null
New-Item -ItemType Directory -Force -Path $textEncoderDir | Out-Null

function Download-File([string]$Url, [string]$Path, [string]$Label) {
  if (Test-Path $Path) {
    Write-Host "[SKIP] $Label already exists: $Path" -ForegroundColor Yellow
    return
  }
  Write-Host "[GET]  $Label" -ForegroundColor Cyan
  Invoke-WebRequest -Uri $Url -OutFile $Path
  if (-not (Test-Path $Path) -or (Get-Item $Path).Length -lt 1024) {
    throw "Download failed or produced an invalid file: $Path"
  }
  Write-Host "[OK]   $Path" -ForegroundColor Green
}

Download-File $checkpointUrl $checkpoint "LTX-Video 0.9.5 2B checkpoint"
Download-File $textEncoderUrl $textEncoder "T5 FP16 text encoder"
Download-File $licenseUrl $checkpointLicense "LTX-Video 0.9.5 model license"

Write-Host ""
Write-Host "Model files are installed locally." -ForegroundColor Green
Write-Host "Next: run check-local-ai.ps1, then start ComfyUI and the backend."
