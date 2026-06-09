# ────────────────────────────────────────
# deploy.ps1
# Handles imports + terraform apply
# ────────────────────────────────────────

param(
    [string]$ProjectId,
    [string]$ProjectNumber,
    [string]$Region = "us-central1",
    [string]$BucketName = "ai_blog_generator_outputs",
    [string]$ImageTag
)

# ────────────────────────────────────────
# Navigate to terraform directory
# ────────────────────────────────────────
$terraformDir = Join-Path $PSScriptRoot "my-terraform"

if (-not (Test-Path $terraformDir)) {
    Write-Host "[ERROR] Terraform directory not found at $terraformDir" -ForegroundColor Red
    exit 1
}

Set-Location $terraformDir
Write-Host "[DIR] Working directory: $terraformDir" -ForegroundColor Cyan

# ────────────────────────────────────────
# Read API keys from environment variables
# ────────────────────────────────────────
$openaiKey = $env:OPENAI_API_KEY
$googleKey = $env:GOOGLE_API_KEY
$tavilyKey = $env:TAVILY_API_KEY

if (-not $openaiKey) { Write-Host "[ERROR] OPENAI_API_KEY env var is not set" -ForegroundColor Red; exit 1 }
if (-not $googleKey) { Write-Host "[ERROR] GOOGLE_API_KEY env var is not set" -ForegroundColor Red; exit 1 }
if (-not $tavilyKey) { Write-Host "[ERROR] TAVILY_API_KEY env var is not set" -ForegroundColor Red; exit 1 }

$tfVars = @(
    "-var", "project_id=$ProjectId",
    "-var", "project_number=$ProjectNumber",
    "-var", "region=$Region",
    "-var", "bucket_name=$BucketName",
    "-var", "image_tag=$ImageTag",
    "-var", "openai_api_key=$openaiKey",
    "-var", "google_api_key=$googleKey",
    "-var", "tavily_api_key=$tavilyKey"
)

# ────────────────────────────────────────
# Step 0 -- Set GCP Project
# ────────────────────────────────────────
Write-Host ""
Write-Host "[GCP] Setting active project to $ProjectId..." -ForegroundColor Yellow
gcloud config set project $ProjectId

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to set GCP project!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] GCP project set to $ProjectId" -ForegroundColor Green

# ────────────────────────────────────────
# Step 1 -- Terraform Init
# ────────────────────────────────────────
Write-Host ""
Write-Host "[INIT] Initializing Terraform..." -ForegroundColor Yellow
terraform init

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Terraform init failed!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Terraform init successful!" -ForegroundColor Green

# ────────────────────────────────────────
# Step 2 -- Check & Import GCS Bucket
# ────────────────────────────────────────
Write-Host ""
Write-Host "[CHECK] Checking if GCS bucket exists..." -ForegroundColor Yellow
$bucketExists = gcloud storage buckets describe "gs://$BucketName" 2>$null
if ($bucketExists) {
    Write-Host "[OK] Bucket exists -- importing into Terraform state..." -ForegroundColor Green
    terraform import @tfVars google_storage_bucket.blog_outputs $BucketName 2>$null
} else {
    Write-Host "[NEW] Bucket does not exist -- Terraform will create it" -ForegroundColor Blue
}

# ────────────────────────────────────────
# Step 3 -- Check & Import Cloud Run
# ────────────────────────────────────────
Write-Host ""
Write-Host "[CHECK] Checking if Cloud Run service exists..." -ForegroundColor Yellow
$cloudRunExists = gcloud run services describe blog-generation-agent --region=$Region 2>$null
if ($cloudRunExists) {
    Write-Host "[OK] Cloud Run service exists -- importing into Terraform state..." -ForegroundColor Green
    terraform import @tfVars google_cloud_run_v2_service.blog_agent "projects/$ProjectId/locations/$Region/services/blog-generation-agent" 2>$null
} else {
    Write-Host "[NEW] Cloud Run service does not exist -- Terraform will create it" -ForegroundColor Blue
}

# ────────────────────────────────────────
# Step 4 -- Check & Import Secrets
# ────────────────────────────────────────
Write-Host ""
Write-Host "[CHECK] Checking if secrets exist in Terraform state..." -ForegroundColor Yellow
$secretInState = terraform state list 2>$null | Select-String "google_secret_manager_secret.openai_key"
if (-not $secretInState) {
    $secretExists = gcloud secrets describe OPENAI_API_KEY 2>$null
    if ($secretExists) {
        Write-Host "[OK] Secrets exist outside Terraform -- importing into state..." -ForegroundColor Green
        terraform import @tfVars "google_secret_manager_secret.openai_key[0]" "projects/$ProjectId/secrets/OPENAI_API_KEY" 2>$null
        terraform import @tfVars "google_secret_manager_secret.google_key[0]" "projects/$ProjectId/secrets/GOOGLE_API_KEY" 2>$null
        terraform import @tfVars "google_secret_manager_secret.tavily_key[0]" "projects/$ProjectId/secrets/TAVILY_API_KEY" 2>$null
        Write-Host "[OK] Secrets imported" -ForegroundColor Green
    } else {
        Write-Host "[NEW] Secrets do not exist -- Terraform will create them" -ForegroundColor Blue
    }
} else {
    Write-Host "[OK] Secrets already in Terraform state -- skipping import" -ForegroundColor Green
}

# ────────────────────────────────────────
# Step 5 -- Terraform Apply
# ────────────────────────────────────────
Write-Host ""
Write-Host "[DEPLOY] Running terraform apply..." -ForegroundColor Yellow

terraform apply -auto-approve @tfVars

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Terraform apply failed!" -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────
# Step 6 -- Retrieve Cloud Run URL
# ────────────────────────────────────────
Write-Host ""
Write-Host "[INFO] Retrieving Cloud Run URL..." -ForegroundColor Yellow
$cloudRunUrl = gcloud run services describe blog-generation-agent --region=$Region --format='value(uri)' --project=$ProjectId 2>$null
if ($LASTEXITCODE -ne 0 -or -not $cloudRunUrl) {
    Write-Host "[WARN] Could not determine Cloud Run URL automatically" -ForegroundColor Yellow
    $cloudRunUrl = "unknown"
} else {
    Write-Host "[OK] Cloud Run URL: $cloudRunUrl" -ForegroundColor Green
}

# ────────────────────────────────────────
# Deploy complete
# ────────────────────────────────────────
# ────────────────────────────────────────

Write-Host "========================================" -ForegroundColor Green
Write-Host "   Deployment Complete!                 " -ForegroundColor Green
Write-Host "   App URL: $cloudRunUrl" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
exit 0
