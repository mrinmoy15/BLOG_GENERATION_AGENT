output "cloud_run_url" {
  description = "The URL of the deployed Cloud Run service (internal)"
  value       = google_cloud_run_v2_service.blog_agent.uri
}

output "firebase_hosting_url" {
  description = "The Firebase Hosting URL (public-facing)"
  value       = "https://norse-rampart-273715.web.app"
}

output "bucket_name" {
  description = "GCS Bucket Name"
  value       = google_storage_bucket.blog_outputs.name
}
