output "backend_url" {
  description = "Cloud Run URL for the backend API service"
  value       = google_cloud_run_v2_service.blog_agent.uri
}

output "frontend_url" {
  description = "Cloud Run URL for the frontend service (public entry point)"
  value       = google_cloud_run_v2_service.blog_agent_frontend.uri
}

output "bucket_name" {
  description = "GCS Bucket Name"
  value       = google_storage_bucket.blog_outputs.name
}
