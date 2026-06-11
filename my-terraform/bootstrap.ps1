# bootstrap.ps1
# Creates the GCP project and grants the deployer account owner rights
# so that the main Terraform module can run without pre-existing permissions.
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (gcloud auth login)
#   - The authenticated account must have resourcemanager.projects.create
#     on the target org/folder (or be a free-tier personal account)
#
# Usage:
#   .\bootstrap.ps1 -ProjectId "your-project-id" -BillingAccount "XXXXXX-XXXXXX-XXXXXX"
#   .\bootstrap.ps1 -ProjectId "your-project-id" -BillingAccount "XXXXXX-XXXXXX-XXXXXX" -OrgId "123456789"
#   .\bootstrap.ps1 -ProjectId "your-project-id" -BillingAccount "XXXXXX-XXXXXX-XXXXXX" -SkipBilling

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,

    [Parameter(Mandatory = $true)]
    [string]$BillingAccount,

    [Parameter(Mandatory = $false)]
    [string]$OrgId,

    [Parameter(Mandatory = $false)]
    [string]$FolderId,

    # Set this flag if your account does not have billing.resourceAssociations.create
    # on the billing account (e.g. org-managed billing). An org/billing admin must
    # link the billing account manually before you run this script.
    [switch]$SkipBilling
)

$PROJECT_ID = $ProjectId
$DEPLOYER   = gcloud config get-value account 2>$null

# --- 1. Check if project already exists --------------------------------------
Write-Host "Checking if project '$PROJECT_ID' already exists..."
$existing = gcloud projects describe $PROJECT_ID --format="value(projectId)" 2>$null
if ($existing -eq $PROJECT_ID) {
    Write-Host "Project already exists -- skipping creation."
} else {
    Write-Host "Creating project '$PROJECT_ID'..."

    $createArgs = @("projects", "create", $PROJECT_ID, "--name=$PROJECT_ID")

    if ($OrgId) {
        $createArgs += "--organization=$OrgId"
    } elseif ($FolderId) {
        $createArgs += "--folder=$FolderId"
    }

    gcloud @createArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create project. Ensure your account has resourcemanager.projects.create permission."
        exit 1
    }
    Write-Host "Project created."
}

# --- 2. Link billing account -------------------------------------------------
if ($SkipBilling) {
    Write-Host "Skipping billing link (--SkipBilling set)."
    Write-Host "ACTION REQUIRED: Ask your org/billing admin to run:"
    Write-Host "  gcloud billing projects link $PROJECT_ID --billing-account=$BillingAccount"
    Write-Host "Then re-run this script with -SkipBilling to complete IAM setup."
} else {
    Write-Host "Linking billing account '$BillingAccount'..."
    gcloud billing projects link $PROJECT_ID --billing-account=$BillingAccount
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Could not link billing account. This usually means your account"
        Write-Host "does not have 'billing.resourceAssociations.create' on billing account '$BillingAccount'."
        Write-Host ""
        Write-Host "Two options:"
        Write-Host "  A) Ask your org/billing admin to run:"
        Write-Host "       gcloud billing projects link $PROJECT_ID --billing-account=$BillingAccount"
        Write-Host "     Then re-run: make bootstrap-gcp"
        Write-Host ""
        Write-Host "  B) Link it yourself in the GCP Console:"
        Write-Host "     Console -> Billing -> My Projects -> Link a project -> select '$PROJECT_ID'"
        Write-Host "     Then re-run: make bootstrap-gcp"
        Write-Host ""
        Write-Host "  C) If billing is already linked, skip this step:"
        Write-Host "     powershell -ExecutionPolicy Bypass -File ./my-terraform/bootstrap.ps1 -BillingAccount '$BillingAccount' -SkipBilling"
        exit 1
    }
    Write-Host "Billing account linked."
}

# --- 3. Grant deployer roles/owner -------------------------------------------
# Owner is required so Terraform can self-assign the fine-grained roles
# (editor, iam.securityAdmin, secretmanager.admin) defined in main.tf.
Write-Host "Granting roles/owner to '$DEPLOYER'..."
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="user:$DEPLOYER" `
    --role="roles/owner"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to grant IAM role. The account running this script must have resourcemanager.projects.setIamPolicy on the project."
    exit 1
}
Write-Host "IAM binding applied."

# --- 4. Summary --------------------------------------------------------------
Write-Host ""
Write-Host "Bootstrap complete. You can now run Terraform:"
Write-Host "  cd my-terraform"
Write-Host "  terraform init"
Write-Host "  terraform apply -var=""project_id=$PROJECT_ID"" ..."
