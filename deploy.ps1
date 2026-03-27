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
Write-Host "[CHECK] Checking if secrets exist..." -ForegroundColor Yellow
$secretExists = gcloud secrets describe OPENAI_API_KEY 2>$null
if ($secretExists) {
    Write-Host "[OK] Secrets exist -- importing into Terraform state..." -ForegroundColor Green
    terraform import @tfVars "google_secret_manager_secret.openai_key[0]" "projects/$ProjectId/secrets/OPENAI_API_KEY" 2>$null
    terraform import @tfVars "google_secret_manager_secret.google_key[0]" "projects/$ProjectId/secrets/GOOGLE_API_KEY" 2>$null
    terraform import @tfVars "google_secret_manager_secret.tavily_key[0]" "projects/$ProjectId/secrets/TAVILY_API_KEY" 2>$null

    # Auto set create_secrets to false
    $tfvarsPath = Join-Path $terraformDir "terraform.tfvars"
    (Get-Content $tfvarsPath) -replace 'create_secrets\s*=\s*true', 'create_secrets = false' | Set-Content $tfvarsPath
    Write-Host "[OK] Set create_secrets = false in terraform.tfvars" -ForegroundColor Green
} else {
    Write-Host "[NEW] Secrets do not exist -- Terraform will create them" -ForegroundColor Blue

    # Auto set create_secrets to true
    $tfvarsPath = Join-Path $terraformDir "terraform.tfvars"
    (Get-Content $tfvarsPath) -replace 'create_secrets\s*=\s*false', 'create_secrets = true' | Set-Content $tfvarsPath
    Write-Host "[OK] Set create_secrets = true in terraform.tfvars" -ForegroundColor Blue
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
# Step 6 -- Grant Firebase Hosting permission to invoke Cloud Run
# ────────────────────────────────────────
Write-Host ""
Write-Host "[IAM] Granting Firebase Hosting service agent Cloud Run invoker role..." -ForegroundColor Yellow
$firebaseSA = "service-$ProjectNumber@gcp-sa-firebasehosting.iam.gserviceaccount.com"
gcloud run services add-iam-policy-binding blog-generation-agent `
    --region=$Region `
    --member="serviceAccount:$firebaseSA" `
    --role="roles/run.invoker" `
    --project=$ProjectId 2>$null

Write-Host "[OK] Firebase Hosting IAM binding set" -ForegroundColor Green

# ────────────────────────────────────────
# Step 7 -- Deploy Firebase Hosting
# ────────────────────────────────────────
Write-Host ""
Write-Host "[FIREBASE] Deploying Firebase Hosting..." -ForegroundColor Yellow
Set-Location $PSScriptRoot
firebase deploy --only hosting

if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] Firebase deploy failed -- hosting URL may not be updated" -ForegroundColor Yellow
} else {
    Write-Host "[OK] Firebase Hosting deployed" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "   Deployment Complete!                 " -ForegroundColor Green
Write-Host "   App URL: https://$ProjectId.web.app  " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green