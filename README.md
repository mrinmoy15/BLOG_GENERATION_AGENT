# BlogForge - AI Blog Generation Agent

A full-stack AI agent that turns any technical topic into a publication-ready blog post. Built with LangGraph for the agentic pipeline, FastAPI for the backend, and a TypeScript/Vite frontend with live streaming progress.

---

## How it works

```
Topic Input
    --> Router         - decides if web research is needed (closed_book / hybrid / open_book)
    --> Research       - searches the web via Tavily and synthesises evidence
    --> Orchestrator   - plans the blog structure (5-9 sections)
    --> Workers (xN)   - writes each section in parallel
    --> Merge          - assembles sections in order
    --> Image Planner  - decides where diagrams would help
    --> Image Gen      - generates images via Gemini and embeds them
    --> Output         - saves final .md file to disk
```

Progress streams live to the UI via Server-Sent Events (SSE) so you can watch each node complete in real time.

---

## Project structure

```
.
+-- src/
|   +-- core/                   # LangGraph agent
|       +-- main_graph.py       # graph topology
|       +-- nodes.py            # all node functions
|       +-- state.py            # LangGraph state schema
|       +-- conditionals.py     # routing + fanout logic
|       +-- reducer_subgraph.py # merge/image subgraph
|       +-- pydantic_models.py  # all Pydantic schemas
|       +-- utils.py            # Tavily search, image gen, helpers
|
+-- api/
|   +-- app.py                  # FastAPI app + SSE + sync endpoints
|   +-- schemas.py              # request/response models
|
+-- frontend/
|   +-- Dockerfile              # nginx image: builds Vite + proxies API
|   +-- nginx.conf              # nginx config template (BACKEND_URL injected at runtime)
|   +-- index.html
|   +-- package.json
|   +-- package-lock.json
|   +-- tsconfig.json
|   +-- src/
|       +-- main.ts             # app entry point
|       +-- api.ts              # SSE + fetch wrappers
|       +-- types.ts            # TypeScript interfaces
|       +-- vite-env.d.ts       # Vite environment type declarations
|       +-- components/
|       |   +-- InputPanel.ts   # topic input form
|       |   +-- ProgressStream.ts # live node progress feed
|       |   +-- ResultPanel.ts  # markdown preview + editor + download
|       |   +-- Sidebar.ts      # sidebar navigation
|       |   +-- Toast.ts        # notifications
|       +-- styles/
|           +-- main.css
|
+-- my-terraform/               # Terraform IaC for GCP infrastructure
|   +-- main.tf
|   +-- variables.tf
|   +-- outputs.tf
|   +-- bootstrap.ps1           # one-time script: create GCP project + link billing + grant IAM owner
|
+-- outputs/                    # generated .md files saved here
+-- Dockerfile
+-- compose.yaml
+-- Makefile                    # build / deploy shortcuts
+-- deploy.ps1                  # PowerShell: build images + IAM bootstrap + Terraform deploy
+-- Explore.ipynb               # exploratory notebook
+-- pyproject.toml
+-- requirements.txt
+-- uv.lock
+-- GCP_DEPLOYMENT_STEPS_ADHOC.MD
+-- GCP_DEPLOYMENT_PRODUCTION.MD
+-- LICENSE
+-- .env.example
+-- README.md
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Python | 3.11+ | |
| Node.js | 18+ LTS | https://nodejs.org |
| npm | 9+ | bundled with Node |
| OpenAI API key | - | for LLM calls |
| Tavily API key | - | for web search (free tier available at https://tavily.com) |
| Google API key | - | for Gemini image generation (optional - app works without it) |

---

## Local setup

### 1. Clone the repo

```powershell
git clone <your-repo-url>
cd Blog_Generation_Agent
```

### 2. Set up environment variables

Create a `.env` file in the project root with the following keys:
```env
OPENAI_API_KEY=sk-...
TAVILY_API_KEY=tvly-...
GOOGLE_API_KEY=...        # optional - only needed for image generation
```

### 3. Install Python dependencies

```powershell
pip install -r requirements.txt
```

> **Windows tip:** if you hit a `uv trampoline` error, use `python -m pip install -r requirements.txt` instead.

### 4. Install frontend dependencies

```powershell
cd frontend
npm install
cd ..
```

---

## Running locally

You need **two terminals** running simultaneously.

### Terminal 1 - Backend (FastAPI)

```powershell
# From the project root
python -m uvicorn api.app:app --reload --port 8000
# or
make run-backend
```

The API will be available at:
- `http://localhost:8000` - API root
- `http://localhost:8000/health` - health check
- `http://localhost:8000/docs` - auto-generated Swagger UI

### Terminal 2 - Frontend (Vite dev server)

```powershell
cd frontend; npm run dev
# or (from project root)
make run-frontend
```

The UI will be available at `http://localhost:5173`.

---

## Using the app

1. Open `http://localhost:5173` in your browser
2. Type a technical topic in the input box (e.g. "How KV cache works in LLM inference")
3. Select a model (GPT-4o recommended)
4. Click **Generate Blog** or press `Ctrl + Enter`
5. Watch the pipeline progress live in the terminal feed on the right
6. When complete:
   - **Preview** tab renders the final markdown
   - **Edit** tab lets you make changes before downloading
   - **Download** saves the `.md` file locally
   - **Copy** copies raw markdown to clipboard
7. The `.md` file is also saved automatically to the `outputs/` folder on the server

---

## API endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Health check |
| `POST` | `/generate/stream` | SSE streaming generation |
| `POST` | `/generate` | Synchronous generation (no streaming) |

### POST `/generate/stream` - request body

```json
{
  "topic": "How attention mechanisms work in transformers",
  "model": "gpt-4o",
  "output_dir": "outputs"
}
```

### SSE event types

| Event | Payload | Description |
|---|---|---|
| `node_done` | `{ "node": "router", "label": "Analysing topic" }` | A pipeline node completed |
| `result` | `{ "filename": "blog.md", "markdown": "..." }` | Final blog ready |
| `error` | `{ "message": "..." }` | Something went wrong |

---

## Configuration

### Switching models

Pass any OpenAI model name in the request body or select from the UI dropdown:

```json
{ "model": "gpt-4o-mini" }
{ "model": "gpt-4o" }
{ "model": "gpt-4-turbo" }
```

### Disabling image generation

Image generation via Gemini is optional. If `GOOGLE_API_KEY` is not set, the agent will gracefully skip image generation and output a clean markdown file with placeholder blocks instead of images.

### Output directory

Generated files are saved to `outputs/` by default. You can change this per-request:

```json
{ "output_dir": "my_custom_folder" }
```

In GCP it is stored in the Cloud Storage bucket defined by `GCS_BUCKET` in your `.env`.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `npm: not recognized` | Install Node.js from https://nodejs.org then restart your terminal |
| `npm error ENOENT package.json` | Run `npm install` from inside the `frontend/` folder, not the project root |
| `Failed to resolve import "./styles/main.css"` | Create `frontend/src/styles/` folder and ensure `main.css` is inside it |
| `uv trampoline failed` | Use `python -m uvicorn ...` and `python -m pip install ...` instead of bare commands |
| `Cannot reach the API` toast on load | Make sure the FastAPI server is running on port 8000 |
| `from schemas import ...` error | Launch uvicorn from the project root: `python -m uvicorn api.app:app ...` |
| `UREQ_PROJECT_BILLING_NOT_FOUND` during terraform apply | Billing is not linked to the project. Run `make bootstrap-gcp` or link via GCP Console -> Billing -> My Projects |
| `The requested bucket name is not available` | The `GCS_BUCKET` name is taken globally (e.g. by a recently deleted project). Change `GCS_BUCKET` in `.env` to a new unique name and re-deploy |
| `Permission denied on secret ... for Revision service account` | `GCP_PROJECT_NUMBER` in `.env` is wrong. Run `gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"` and update `.env` |
| `[IMPORT] Checking for existing GCP resources...` hangs | APIs are not yet enabled on a new project. Interrupt with `Ctrl+C` and re-run with `make deploy-image SKIP_IMPORT=1` |
| `lifecycleState: DELETE_REQUESTED` | Project is scheduled for deletion. Restore it with `gcloud projects undelete YOUR_PROJECT_ID` |
| Terraform apply fails with 403 on old project resources | Old `terraform.tfstate` references a deleted project. Back it up and delete it: `Copy-Item terraform.tfstate terraform.tfstate.bak; Remove-Item terraform.tfstate` |

---

## Run with Docker Compose (alternative to the two-terminal setup)

If you have Docker installed, this builds and runs both services with one command - no separate Python or Node.js setup needed:

```powershell
make build
```

| Service | URL |
|---|---|
| Frontend (nginx) | http://localhost:5173 |
| Backend API (FastAPI) | http://localhost:8000 |

The frontend container proxies all API calls (`/health`, `/generate`, `/blogs`, `/outputs`) to the backend container, so there are no CORS issues.

```powershell
make down      # stop both containers
make logs      # tail logs from both containers
```

---

## Deploy to Cloud Run

### Prerequisites - install once

| Tool | Install |
|---|---|
| Docker Desktop | https://docker.com |
| Google Cloud SDK | https://cloud.google.com/sdk/docs/install |
| Terraform | https://developer.hashicorp.com/terraform/install - download AMD64 for Windows, extract to `C:\terraform\` |
| Docker Hub account | https://hub.docker.com - free |

After installing Terraform, add it to PATH permanently and verify:
```powershell
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\terraform", "User")
# restart your terminal, then:
terraform -version
```

---

### Step 1 - Bootstrap the GCP project

If the GCP project does not yet exist, run this once to create it, link your billing account, and grant your account the permissions Terraform needs:

```powershell
# Authenticate first (if you haven't already)
gcloud auth login
gcloud auth application-default login

# Then bootstrap (BILLING_ACCOUNT is read from .env automatically)
make bootstrap-gcp
```

This runs `my-terraform/bootstrap.ps1` which:
1. Creates the project defined by `GCP_PROJECT_ID` in your `.env` (skips silently if it already exists)
2. Links the billing account from `BILLING_ACCOUNT` in your `.env`
3. Grants `roles/owner` to your deployer account so Terraform can self-manage IAM

> **Billing permission error?** If your account does not have `billing.resourceAssociations.create` on the billing account (common in org-managed accounts), the billing link step will fail. Either ask your org admin to run `gcloud billing projects link YOUR_PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT`, or link it via GCP Console -> Billing -> My Projects. Then re-run `make bootstrap-gcp`.

To find your billing account ID:
```powershell
gcloud billing accounts list
```
Or go to GCP Console -> Billing - the ID is shown in `XXXXXX-XXXXXX-XXXXXX` format at the top.

Note down your **Project Number** after creation (needed in `.env`):
```powershell
gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"
```

---

### Step 2 - Authenticate with GCP

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

---

### Step 3 - Log in to Docker Hub

```powershell
docker login
```

---

### Step 4 - Set your API keys as environment variables

These get stored in GCP Secret Manager during deployment:
```powershell
$env:OPENAI_API_KEY = "sk-..."
$env:GOOGLE_API_KEY = "AIza..."
$env:TAVILY_API_KEY = "tvly-..."
```

---

### Step 5 - Update `.env` with your GCP values

Open `.env` and fill in these fields:
```env
DOCKER_USERNAME=your-dockerhub-username
APP_NAME=ai-blog-generator
APP_VERSION=1.0.0

GCP_PROJECT_ID=your-project-id
GCP_PROJECT_NUMBER=your-project-number
GCP_REGION=us-central1
GCS_BUCKET=your-unique-bucket-name
BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX
```

> **Important - `GCP_PROJECT_NUMBER`:** This must be the project number of the project you are deploying to, not a previous project. Get the correct value with:
> ```powershell
> gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"
> ```
> Using the wrong project number means the Compute service account IAM bindings will target the wrong account and Cloud Run will fail to access secrets.

> **Important - `GCS_BUCKET`:** GCS bucket names are globally unique across all GCP projects and all users. If you previously deployed to a different project, the old bucket name is still reserved for up to 30 days after that project is deleted. Choose a new unique name (e.g. append your project suffix: `my-bucket-2199`).

---

### Step 6 - Deploy

Run this single command from the project root:
```powershell
make deploy-image
```

> **Brand new project?** The import step checks for existing GCP resources and can hang on a project where no APIs are enabled yet. Skip it with:
> ```powershell
> make deploy-image SKIP_IMPORT=1
> ```

This single script (`deploy.ps1`) does everything in order:
1. Build `ai-blog-generator-backend:TAG` from the root `Dockerfile`
2. Build `ai-blog-generator-frontend:TAG` from `frontend/Dockerfile`
3. Push both images to Docker Hub
4. **Bootstrap IAM** - checks which of `roles/editor`, `roles/iam.securityAdmin`, and `roles/secretmanager.admin` are already granted; adds only the missing ones. Only waits 60s for propagation when new bindings are actually added - re-deploys skip the wait entirely
5. Run Terraform - provisions the backend Cloud Run service first, then the frontend Cloud Run service with `BACKEND_URL` automatically wired to the backend's URI
6. Print both URLs when done

> **First deploy only:** The bootstrap requires your account to already be a project owner (true if you created the GCP project). If it fails, you'll see the exact `gcloud` command to ask your project owner to run once.

---

### Step 7 - Get your URLs

Both URLs are printed at the end of the deployment output:
```
========================================
   Deployment Complete!
   Frontend : https://blog-generation-agent-frontend-xxxx-uc.a.run.app
   Backend  : https://blog-generation-agent-xxxx-uc.a.run.app
========================================
```

You can also retrieve them at any time:
```powershell
# Frontend (share this with users) - replace APP_NAME and GCP_REGION with your .env values
gcloud run services describe YOUR_APP_NAME-frontend --region=YOUR_GCP_REGION --format="value(uri)"

# Backend API
gcloud run services describe YOUR_APP_NAME --region=YOUR_GCP_REGION --format="value(uri)"
```

**The Frontend URL is the one you open in a browser.** It serves the UI and proxies all API calls to the backend - users only ever need this one URL.

---

### Re-deploying after code changes

```powershell
make deploy-image
```

A new timestamped tag is auto-generated. Both images are rebuilt, pushed, and both Cloud Run services are updated in one command.

---

## Roadmap

- [x] LangGraph agentic pipeline (router -> research -> orchestrator -> workers -> reducer)
- [x] Live SSE streaming progress
- [x] Markdown preview + editor + download
- [x] FastAPI backend
- [x] TypeScript/Vite frontend
- [x] Docker setup
- [x] GCP Deployment
- [ ] Authentication
- [ ] Blog history / saved generations
- [ ] Support for Anthropic Claude and Gemini as LLM backends

## Tech stack

| Layer | Technology |
|---|---|
| Agent framework | LangGraph |
| LLM | OpenAI GPT-4o (via LangChain) |
| Web search | Tavily |
| Image generation | Google Gemini |
| Backend | FastAPI + Uvicorn |
| Frontend | TypeScript + Vite (no framework) |
| Streaming | Server-Sent Events (SSE) |
| Markdown rendering | marked.js |
