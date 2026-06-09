## GCP Deployment Production (Using Terraform)

#### Step1: Download Terraform AMD64 version for windows from [terraform download](https://developer.hashicorp.com/terraform/install)  
- Extract to a simple path like C:\terraform\  
- Add to PATH using: `[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\terraform", "User")`
- Restart your terminal and verify: `terraform -version` 
  
#### Step 2 — Project Structure  
The Terraform files are already in the repo:
```
my-terraform/
├── main.tf
├── variables.tf
└── outputs.tf
```
All variable values are passed at deploy time via environment variables — no `terraform.tfvars` file is needed.

#### Step4 — Deployment  
Set the temporary env variables in your powershell
```powershell
$env:OPENAI_API_KEY = "your-actual-openai-key"
$env:GOOGLE_API_KEY = "your-actual-google-key"
$env:TAVILY_API_KEY = "your-actual-tavily-key"
```

Do authentication:
```powershell
gcloud auth application-default login
```

Run the Deploy command:
```powershell
make deploy-image
```