## GCP Deployment Adhoc (Using the GCP CLI)

#### Step 1 — Set up GCP
- Go to console.cloud.google.com
- Create a new project (or select an existing one)
- Enable billing on the project
- Enable these APIs (search in the console):
  `Cloud Run API`
  `Cloud Storage API`

#### Step 2 — Install Google Cloud CLI
Download and install from cloud.google.com/sdk/docs/install  
Once install is done, to add to path permanently run the following:    
```bash
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin", "User")
```
  
Create the folder to save credential locally  
```bash
New-Item -ItemType Directory -Force -Path "$env:APPDATA\Roaming\gcloud\legacy_credentials\mrinmoybhuyan007@gmail.com"
```

Grant full permissions 
```bash 
icacls "$env:APPDATA\gcloud" /grant "${env:USERNAME}:(OI)(CI)F" /T
```

Then run the following command to authenticate  
```bash
gcloud auth login 
gcloud config set project YOUR_PROJECT_ID
```

#### Step 3 — Create a GCS bucket for images  
Run the following commands
```bash 
gcloud storage buckets create gs://your_bucket_name --location=us-central1
```  

Make images publicly readable  
```bash 
gcloud storage buckets add-iam-policy-binding gs://your-bucket-name --member=allUsers --role=roles/storage.objectViewer
```

#### Step 4 — Grant Cloud Run access to write to the bucket  
Get your project number  
```bash
gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"
```

Enable compute engine API first  
```bash
gcloud services enable compute.googleapis.com
```

Grant the default Cloud Run service account write access  
```bash  
gcloud storage buckets add-iam-policy-binding gs://your-bucket-name --member=serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com --role=roles/storage.objectCreator
```

#### Step 5 — Deploy to Cloud Run

Enable Secret  
```bash
gcloud services enable secretmanager.googleapis.com
```
 
Create Secrets  
```bash
echo "YOUR OPEN AI API KEY" | gcloud secrets create OPENAI_API_KEY --data-file=-
echo "YOUR GOOGLE API KEY" | gcloud secrets create GOOGLE_API_KEY --data-file=-   
echo "YOUR TAVILY API KEY" | gcloud secrets create TAVILY_API_KEY --data-file=-
``` 
  
Grant Cloud Run access to the secrets   
```bash
$PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)") 
  
gcloud secrets add-iam-policy-binding OPENAI_API_KEY --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/secretmanager.secretAccessor"
  
gcloud secrets add-iam-policy-binding GOOGLE_API_KEY --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/secretmanager.secretAccessor" 
  
gcloud secrets add-iam-policy-binding TAVILY_API_KEY --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/secretmanager.secretAccessor"
```  

Deploy   
   
```bash
gcloud run deploy blog-generation-agent \
  --image=docker.io/mrinmoy15/ai-blog-generator:1.0.0 \
  --platform=managed \
  --region=us-central1 \
  --port=8000 \
  --allow-unauthenticated \
  --set-env-vars="GCS_BUCKET=ai_blog_generator_outputs" \
  --set-secrets="OPENAI_API_KEY=OPENAI_API_KEY:latest,GOOGLE_API_KEY=GOOGLE_API_KEY:latest,TAVILY_API_KEY=TAVILY_API_KEY:latest" \
  --memory=2Gi \
  --cpu=2
```

  
#### Step 6: Get the application link   
You see the link in your terminal once deployed successfully. Here is the link for this app I deployed  

(AI-Blog-Generator)[https://norse-rampart-273715.web.app/]

