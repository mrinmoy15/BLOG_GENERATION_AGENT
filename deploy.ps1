# ----------------------------------------
# deploy.ps1
# Build images, push to Docker Hub, bootstrap IAM, and deploy to GCP Cloud Run via Terraform
# ----------------------------------------

param(
    [string]$ProjectId,
    [string]$ProjectNumber,
    [string]$Region      = "us-central1",
    [string]$BucketName,
    [string]$DockerUsername,
    [string]$ImageName   = "ai-blog-generator",
    [string]$ImageTag,
    [switch]$SkipImport
)

# ----------------------------------------
# Validate required parameters
# ----------------------------------------
if (-not $ProjectId)      { Write-Host "[ERROR] -ProjectId is required. Set GCP_PROJECT_ID in .env"      -ForegroundColor Red; exit 1 }
if (-not $ProjectNumber)  { Write-Host "[ERROR] -ProjectNumber is required. Set GCP_PROJECT_NUMBER in .env" -ForegroundColor Red; exit 1 }
if (-not $BucketName)     { Write-Host "[ERROR] -BucketName is required. Set GCS_BUCKET in .env"         -ForegroundColor Red; exit 1 }
if (-not $DockerUsername) { Write-Host "[ERROR] -DockerUsername is required. Set DOCKER_USERNAME in .env" -ForegroundColor Red; exit 1 }

# ----------------------------------------
# Auto-generate image tag if not provided
# ----------------------------------------
if (-not $ImageTag) {
    $ImageTag = "1.0.$(Get-Date -Format 'yyyyMMdd-HHmm')"
    Write-Host "[INFO] Auto-generated image tag: $ImageTag" -ForegroundColor Cyan
}

$BackendImage  = "$($DockerUsername)/$($ImageName)-backend:$($ImageTag)"
$FrontendImage = "$($DockerUsername)/$($ImageName)-frontend:$($ImageTag)"
$rootDir       = $PSScriptRoot
$terraformDir  = Join-Path $rootDir "my-terraform"
$frontendDir   = Join-Path $rootDir "frontend"

if (-not (Test-Path $terraformDir)) { Write-Host "[ERROR] Terraform directory not found: $terraformDir" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $frontendDir))  { Write-Host "[ERROR] frontend directory not found: $frontendDir"   -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   AI Blog Generator -- Deploy         " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Backend : $BackendImage"
Write-Host "  Frontend: $FrontendImage"
Write-Host "  Project : $ProjectId  ($Region)"
Write-Host "  Bucket  : $BucketName"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------
# Step 1 -- Build backend image
# ----------------------------------------
Write-Host "[BUILD] Building backend image..." -ForegroundColor Yellow
docker build -t $BackendImage $rootDir
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Backend build failed!" -ForegroundColor Red; exit 1 }
Write-Host "[OK] Backend build successful" -ForegroundColor Green

# ----------------------------------------
# Step 2 -- Build frontend image
# ----------------------------------------
Write-Host ""
Write-Host "[BUILD] Building frontend image..." -ForegroundColor Yellow
docker build -t $FrontendImage $frontendDir
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Frontend build failed!" -ForegroundColor Red; exit 1 }
Write-Host "[OK] Frontend build successful" -ForegroundColor Green

# ----------------------------------------
# Step 3 -- Push backend image
# ----------------------------------------
Write-Host ""
Write-Host "[PUSH] Pushing backend image..." -ForegroundColor Yellow
docker push $BackendImage
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Backend push failed!" -ForegroundColor Red; exit 1 }
Write-Host "[OK] Backend push successful" -ForegroundColor Green

# ----------------------------------------
# Step 4 -- Push frontend image
# ----------------------------------------
Write-Host ""
Write-Host "[PUSH] Pushing frontend image..." -ForegroundColor Yellow
docker push $FrontendImage
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Frontend push failed!" -ForegroundColor Red; exit 1 }
Write-Host "[OK] Frontend push successful" -ForegroundColor Green

# ----------------------------------------
# Step 5 -- Set GCP project + detect account
# ----------------------------------------
Write-Host ""
Write-Host "[GCP] Setting active project to $ProjectId..." -ForegroundColor Yellow
gcloud config set project $ProjectId
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Failed to set GCP project!" -ForegroundColor Red; exit 1 }

$deployerAccount = gcloud config get-value account 2>$null
if (-not $deployerAccount) {
    Write-Host "[ERROR] No active gcloud account. Run: gcloud auth login" -ForegroundColor Red
    exit 1
}
Write-Host "[AUTH] Deploying as: $deployerAccount on $ProjectId" -ForegroundColor Cyan

# ----------------------------------------
# Read API keys from environment
# ----------------------------------------
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
    "-var", "app_name=$ImageName",
    "-var", "deployer_account=$deployerAccount",
    "-var", "docker_username=$DockerUsername",
    "-var", "image_tag=$ImageTag",
    "-var", "frontend_image_tag=$ImageTag",
    "-var", "openai_api_key=$openaiKey",
    "-var", "google_api_key=$googleKey",
    "-var", "tavily_api_key=$tavilyKey"
)

# ----------------------------------------
# Step 6 -- Bootstrap IAM
# Grants are idempotent; only waits for
# propagation if new bindings were added.
# ----------------------------------------
Write-Host ""
Write-Host "[BOOTSTRAP] Checking IAM roles for $deployerAccount..." -ForegroundColor Yellow

$existingRoles = gcloud projects get-iam-policy $ProjectId `
    --flatten="bindings[].members" `
    --filter="bindings.members:user:$deployerAccount" `
    --format="value(bindings.role)" 2>$null

$newGrants = $false
foreach ($role in @("roles/editor", "roles/iam.securityAdmin", "roles/secretmanager.admin")) {
    if ($existingRoles -notcontains $role) {
        Write-Host "  Granting $role..." -ForegroundColor Cyan
        $grantOutput = gcloud projects add-iam-policy-binding $ProjectId `
            --member="user:$deployerAccount" `
            --role=$role `
            --condition=None 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to grant $role" -ForegroundColor Red
            Write-Host "[ERROR] $grantOutput" -ForegroundColor Red
            Write-Host "Ask your project owner to run:" -ForegroundColor Yellow
            Write-Host "  gcloud projects add-iam-policy-binding $ProjectId --member=`"user:$deployerAccount`" --role=`"roles/owner`"" -ForegroundColor White
            exit 1
        }
        Write-Host "  [OK] $role granted" -ForegroundColor Green
        $newGrants = $true
    } else {
        Write-Host "  [OK] $role already present" -ForegroundColor Green
    }
}

if ($newGrants) {
    Write-Host "[WAIT] New IAM bindings added -- waiting 60s for propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
}
Write-Host "[OK] IAM bootstrap complete" -ForegroundColor Green

# ----------------------------------------
# Step 7 -- Terraform init
# ----------------------------------------
Set-Location $terraformDir
Write-Host ""
Write-Host "[INIT] Initializing Terraform..." -ForegroundColor Yellow
terraform init
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Terraform init failed!" -ForegroundColor Red; exit 1 }
Write-Host "[OK] Terraform init successful" -ForegroundColor Green

# ----------------------------------------
# Step 8 -- Import existing resources
# Prevents "already exists" errors on re-deploys.
# ----------------------------------------
Write-Host ""
if ($SkipImport) {
    Write-Host "[IMPORT] Skipping import checks (-SkipImport set)." -ForegroundColor Yellow
} else {
Write-Host "[IMPORT] Checking for existing GCP resources to import..." -ForegroundColor Yellow

$bucketExists = gcloud storage buckets describe "gs://$BucketName" 2>$null
if ($bucketExists) {
    Write-Host "  Importing GCS bucket..." -ForegroundColor Cyan
    terraform import @tfVars google_storage_bucket.blog_outputs $BucketName 2>$null
}

$backendExists = gcloud run services describe $ImageName --region=$Region 2>$null
if ($backendExists) {
    Write-Host "  Importing backend Cloud Run service..." -ForegroundColor Cyan
    terraform import @tfVars google_cloud_run_v2_service.blog_agent "projects/$ProjectId/locations/$Region/services/$ImageName" 2>$null
}

$frontendExists = gcloud run services describe "$ImageName-frontend" --region=$Region 2>$null
if ($frontendExists) {
    Write-Host "  Importing frontend Cloud Run service..." -ForegroundColor Cyan
    terraform import @tfVars google_cloud_run_v2_service.blog_agent_frontend "projects/$ProjectId/locations/$Region/services/$ImageName-frontend" 2>$null
}

$secretInState = terraform state list 2>$null | Select-String "google_secret_manager_secret.openai_key"
if (-not $secretInState) {
    $secretExists = gcloud secrets describe OPENAI_API_KEY 2>$null
    if ($secretExists) {
        Write-Host "  Importing secrets..." -ForegroundColor Cyan
        terraform import @tfVars "google_secret_manager_secret.openai_key[0]" "projects/$ProjectId/secrets/OPENAI_API_KEY" 2>$null
        terraform import @tfVars "google_secret_manager_secret.google_key[0]" "projects/$ProjectId/secrets/GOOGLE_API_KEY" 2>$null
        terraform import @tfVars "google_secret_manager_secret.tavily_key[0]" "projects/$ProjectId/secrets/TAVILY_API_KEY" 2>$null
    }
}

Write-Host "[OK] Import checks complete" -ForegroundColor Green
}

# ----------------------------------------
# Step 9 -- Terraform apply
# ----------------------------------------
Write-Host ""
Write-Host "[DEPLOY] Running terraform apply..." -ForegroundColor Yellow
terraform apply -auto-approve @tfVars
if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] Terraform apply failed!" -ForegroundColor Red; exit 1 }

# ----------------------------------------
# Step 10 -- Print URLs
# ----------------------------------------
$backendUrl  = terraform output -raw backend_url  2>$null
$frontendUrl = terraform output -raw frontend_url 2>$null
if (-not $backendUrl)  { $backendUrl  = "run: terraform output backend_url" }
if (-not $frontendUrl) { $frontendUrl = "run: terraform output frontend_url" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "   Deployment Complete!                 " -ForegroundColor Green
Write-Host "   Frontend : $frontendUrl"
Write-Host "   Backend  : $backendUrl"
Write-Host "========================================" -ForegroundColor Green
