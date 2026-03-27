output "cloud_run_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.blog_agent.uri
}

output "bucket_name" {
  description = "GCS Bucket Name"
  value       = google_storage_bucket.blog_outputs.name
}
