# Load environment variables from .env
include .env
export

# Variables
IMAGE_NAME = $(DOCKER_USERNAME)/ai-blog-generator
VERSION = $(APP_VERSION)

.PHONY: build run down logs push clean firebase-install firebase-deploy deploy-image deploy-initial

## Build the Docker image
build:
	docker-compose up --build

## Run the container without rebuilding
run:
	docker compose up

## Stop and remove the container
down:
	docker compose down

## View container logs
logs:
	docker compose logs -f

## Push image to Docker Hub
push:
	docker compose push

## Remove image locally
clean:
	docker rmi $(IMAGE_NAME):$(VERSION)

## Build and push in one step
release: build push

## Install Firebase CLI (one-time)
firebase-install:
	npm install -g firebase-tools

## Deploy Firebase Hosting (public-facing URL fronting Cloud Run)
firebase-deploy:
	firebase deploy --only hosting

## Build, push and deploy to GCP Cloud Run via Terraform (skips Firebase Hosting)
deploy-image:
	powershell -ExecutionPolicy Bypass -File ./new_image_deploy.ps1 \
		-ProjectId "$(GCP_PROJECT_ID)" \
		-ProjectNumber "$(GCP_PROJECT_NUMBER)" \
		-Region "$(GCP_REGION)" \
		-BucketName "$(GCS_BUCKET)" \
		-ImageTag "$(VERSION)" \
		-SkipFirebase

## First-time setup: build, push, deploy Cloud Run + Firebase Hosting
deploy-initial:
	powershell -ExecutionPolicy Bypass -File ./new_image_deploy.ps1 \
		-ProjectId "$(GCP_PROJECT_ID)" \
		-ProjectNumber "$(GCP_PROJECT_NUMBER)" \
		-Region "$(GCP_REGION)" \
		-BucketName "$(GCS_BUCKET)" \
		-ImageTag "$(VERSION)"