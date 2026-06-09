# Load environment variables from .env
include .env
export

BACKEND_IMAGE  = $(DOCKER_USERNAME)/$(APP_NAME)-backend
FRONTEND_IMAGE = $(DOCKER_USERNAME)/$(APP_NAME)-frontend
VERSION        = $(APP_VERSION)

.PHONY: build run run-backend run-frontend down logs push clean release deploy-image

## Start FastAPI backend locally (with hot reload)
run-backend:
	python -m uvicorn api.app:app --reload --port 8000

## Start Vite frontend dev server locally
run-frontend:
	cd frontend && npm run dev

## Build both backend and frontend images
build:
	docker compose up --build

## Run both containers without rebuilding
run:
	docker compose up

## Stop and remove both containers
down:
	docker compose down

## Tail logs from both containers
logs:
	docker compose logs -f

## Push both images to Docker Hub
push:
	docker compose push

## Remove both images locally
clean:
	docker rmi $(BACKEND_IMAGE):$(VERSION) || true
	docker rmi $(FRONTEND_IMAGE):$(VERSION) || true

## Build and push both images in one step
release: build push

## Build images, push, and deploy to GCP Cloud Run via Terraform
deploy-image:
	powershell -ExecutionPolicy Bypass -File ./deploy.ps1 \
		-ProjectId "$(GCP_PROJECT_ID)" \
		-ProjectNumber "$(GCP_PROJECT_NUMBER)" \
		-Region "$(GCP_REGION)" \
		-BucketName "$(GCS_BUCKET)" \
		-DockerUsername "$(DOCKER_USERNAME)" \
		-ImageName "$(APP_NAME)"
