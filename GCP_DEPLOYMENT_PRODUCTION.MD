## GCP Deployment Production (Using Terraform)

#### Step1: Download Terraform AMD64 version for windows from [terraform download](https://developer.hashicorp.com/terraform/install)  
- Extract to a simple path like C:\terraform\  
- Add to PATH using: `[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\terraform", "User")`
- Restart your terminal and verify: `terraform -version` 
  
#### Step 2 — Create Project Structure  
```
my-terraform/
├── main.tf
├── variables.tf
├── outputs.tf
└── terraform.tfvars
```
  
#### Step 3 — Create the Terraform Files  
Create the files that are shown in the folder structure. The contents in the file is available in the repo.

#### Step4 — Deployment  
Set the temporary env variables in your powershell  

`$env:TF_VAR_openai_api_key = "your-actual-openai-key"` 
   
`$env:TF_VAR_google_api_key = "your-actual-google-key"`
    
`$env:TF_VAR_tavily_api_key = "your-actual-tavily-key"`  
  
Do authentication:  
`gcloud auth application-default login`  
 

Run the Deploy command:  
`make deploy-image`