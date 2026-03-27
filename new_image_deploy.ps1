# ────────────────────────────────────────
# new_image_deploy.ps1
# Full automated build + push + deploy
# ────────────────────────────────────────

param(
    [string]$ProjectId,
    [string]$ProjectNumber,
    [string]$Region = "us-central1",
    [string]$BucketName = "ai_blog_generator_outputs",
    [string]$DockerUsername = "mrinmoy15",
    [string]$ImageName = "ai-blog-generator",
    [string]$ImageTag
)

# ────────────────────────────────────────
# Auto-generate image tag if not provided
# ────────────────────────────────────────
if (-not $ImageTag) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmm"
    $ImageTag = "1.0.$timestamp"
    Write-Host "[INFO] Auto-generated image tag: $ImageTag" -ForegroundColor Cyan
}

$FullImageName = "$DockerUsername/$ImageName`:$ImageTag"

# ────────────────────────────────────────
# Resolve paths
# ────────────────────────────────────────
$rootDir       = $PSScriptRoot
$terraformDir  = Join-Path $rootDir "my-terraform"
$tfvarsPath    = Join-Path $terraformDir "terraform.tfvars"
$deployScript  = Join-Path $rootDir "deploy.ps1"
$dockerfileDir = $rootDir

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   AI Blog Generator -- Deploy Script   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Image  : $FullImageName"
Write-Host "  Region : $Region"
Write-Host "  Project: $ProjectId"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ────────────────────────────────────────
# Validate paths exist
# ────────────────────────────────────────
if (-not (Test-Path $terraformDir)) {
    Write-Host "[ERROR] Terraform directory not found at $terraformDir" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $tfvarsPath)) {
    Write-Host "[ERROR] terraform.tfvars not found at $tfvarsPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $deployScript)) {
    Write-Host "[ERROR] deploy.ps1 not found at $deployScript" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $dockerfileDir)) {
    Write-Host "[ERROR] Dockerfile directory not found at $dockerfileDir" -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────
# Step 1 -- Docker Build
# ────────────────────────────────────────
Write-Host "[BUILD] Building Docker image: $FullImageName" -ForegroundColor Yellow
docker build -t $FullImageName $dockerfileDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Docker build successful!" -ForegroundColor Green

# ────────────────────────────────────────
# Step 2 -- Docker Push
# ────────────────────────────────────────
Write-Host ""
Write-Host "[PUSH] Pushing image to Docker Hub: $FullImageName" -ForegroundColor Yellow
docker push $FullImageName

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker push failed!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Docker push successful!" -ForegroundColor Green

# ────────────────────────────────────────
# Step 3 -- Run deploy.ps1 (terraform import + apply)
# ────────────────────────────────────────
Write-Host ""
Write-Host "[DEPLOY] Running deploy.ps1..." -ForegroundColor Yellow
& $deployScript -ProjectId $ProjectId -ProjectNumber $ProjectNumber -Region $Region -BucketName $BucketName -ImageTag $ImageTag

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "   Full Deploy Complete!                " -ForegroundColor Green
Write-Host "   Image: $FullImageName               " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green