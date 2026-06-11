variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "app_name" {
  description = "Application name - used as Cloud Run service name prefix and image name base"
  type        = string
}

variable "project_number" {
  description = "GCP Project Number"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "GCS Bucket Name - must be globally unique across all GCP projects"
  type        = string
}

variable "openai_api_key" {
  description = "OpenAI API Key"
  type        = string
  sensitive   = true
}

variable "google_api_key" {
  description = "Google API Key"
  type        = string
  sensitive   = true
}

variable "tavily_api_key" {
  description = "Tavily API Key"
  type        = string
  sensitive   = true
}

variable "create_secrets" {
  description = "Set to false if secrets already exist in GCP Secret Manager"
  type        = bool
  default     = true
}

variable "deployer_account" {
  description = "GCP user account email that runs Terraform (granted necessary IAM roles)"
  type        = string
}

variable "docker_username" {
  description = "Docker Hub username used to pull the service images"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag for the backend service"
  type        = string
  default     = "1.0.0"
}

variable "frontend_image_tag" {
  description = "Docker image tag for the frontend service"
  type        = string
  default     = "1.0.0"
}