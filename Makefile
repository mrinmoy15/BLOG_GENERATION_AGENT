# Load environment variables from .env
include .env
export

# Variables
IMAGE_NAME = $(DOCKER_USERNAME)/ai-blog-generator
VERSION = $(APP_VERSION)

.PHONY: build run down logs push clean

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