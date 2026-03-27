variable "project_id" {
  description = "GCP Project ID"
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
  description = "GCS Bucket Name"
  type        = string
  default     = "ai_blog_generator_outputs"
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

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "1.0.0"
}