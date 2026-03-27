terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ────────────────────────────────────────
# Enable APIs
# ────────────────────────────────────────
resource "google_project_service" "cloud_run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secret_manager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "firebase" {
  service            = "firebase.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "firebase_hosting" {
  service            = "firebasehosting.googleapis.com"
  disable_on_destroy = false
}

# ────────────────────────────────────────
# GCS Bucket
# ────────────────────────────────────────
resource "google_storage_bucket" "blog_outputs" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true
}

# Make bucket publicly readable
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.blog_outputs.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Grant Cloud Run service account write access
resource "google_storage_bucket_iam_member" "cloudrun_write" {
  bucket = google_storage_bucket.blog_outputs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.project_number}-compute@developer.gserviceaccount.com"
}

# ────────────────────────────────────────
# Secrets — Conditionally Create
# ────────────────────────────────────────
resource "google_secret_manager_secret" "openai_key" {
  count     = var.create_secrets ? 1 : 0
  secret_id = "OPENAI_API_KEY"
  replication {
    auto {}
  }
  depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_version" "openai_key_value" {
  count       = var.create_secrets ? 1 : 0
  secret      = google_secret_manager_secret.openai_key[0].id
  secret_data = var.openai_api_key
}

resource "google_secret_manager_secret" "google_key" {
  count     = var.create_secrets ? 1 : 0
  secret_id = "GOOGLE_API_KEY"
  replication {
    auto {}
  }
  depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_version" "google_key_value" {
  count       = var.create_secrets ? 1 : 0
  secret      = google_secret_manager_secret.google_key[0].id
  secret_data = var.google_api_key
}

resource "google_secret_manager_secret" "tavily_key" {
  count     = var.create_secrets ? 1 : 0
  secret_id = "TAVILY_API_KEY"
  replication {
    auto {}
  }
  depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_version" "tavily_key_value" {
  count       = var.create_secrets ? 1 : 0
  secret      = google_secret_manager_secret.tavily_key[0].id
  secret_data = var.tavily_api_key
}

# ────────────────────────────────────────
# Locals — Handle both existing & new secrets
# ────────────────────────────────────────
locals {
  service_account = "${var.project_number}-compute@developer.gserviceaccount.com"

  openai_secret_id = var.create_secrets ? google_secret_manager_secret.openai_key[0].id : "projects/${var.project_id}/secrets/OPENAI_API_KEY"
  google_secret_id = var.create_secrets ? google_secret_manager_secret.google_key[0].id : "projects/${var.project_id}/secrets/GOOGLE_API_KEY"
  tavily_secret_id = var.create_secrets ? google_secret_manager_secret.tavily_key[0].id : "projects/${var.project_id}/secrets/TAVILY_API_KEY"
}

# ────────────────────────────────────────
# Secret IAM — Grant Cloud Run access
# ────────────────────────────────────────
resource "google_secret_manager_secret_iam_member" "openai_access" {
  secret_id = local.openai_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.service_account}"
}

resource "google_secret_manager_secret_iam_member" "google_access" {
  secret_id = local.google_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.service_account}"
}

resource "google_secret_manager_secret_iam_member" "tavily_access" {
  secret_id = local.tavily_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.service_account}"
}

# ────────────────────────────────────────
# Cloud Run Service
# ────────────────────────────────────────
resource "google_cloud_run_v2_service" "blog_agent" {
  name     = "blog-generation-agent"
  location = var.region

  template {
    containers {
      image = "docker.io/mrinmoy15/ai-blog-generator:${var.image_tag}"

      ports {
        container_port = 8000
      }

      resources {
        limits = {
          memory = "2Gi"
          cpu    = "2"
        }
      }

      env {
        name  = "GCS_BUCKET"
        value = var.bucket_name
      }

      env {
        name = "OPENAI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "OPENAI_API_KEY"
            version = "latest"
          }
        }
      }

      env {
        name = "GOOGLE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "GOOGLE_API_KEY"
            version = "latest"
          }
        }
      }

      env {
        name = "TAVILY_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "TAVILY_API_KEY"
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.cloud_run,
    google_secret_manager_secret_iam_member.openai_access,
    google_secret_manager_secret_iam_member.google_access,
    google_secret_manager_secret_iam_member.tavily_access,
  ]
}

# ────────────────────────────────────────
# Allow unauthenticated access
# ────────────────────────────────────────
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  name     = google_cloud_run_v2_service.blog_agent.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}