variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "network" {
  type    = string
  default = "default"
}

variable "domain" {
  type = string
}

variable "admin_email" {
  type = string
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content for OS Login / metadata"
}

variable "jibri_count" {
  type    = number
  default = 9
}

variable "control_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "jvb_machine_type" {
  type    = string
  default = "e2-standard-16"
}

variable "jibri_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "control_disk_gb" {
  type    = number
  default = 50
}

variable "jvb_disk_gb" {
  type    = number
  default = 50
}

variable "jibri_disk_gb" {
  type    = number
  default = 30
}

variable "enable_schedule" {
  type    = bool
  default = true
}

variable "schedule_start_cron" {
  type        = string
  description = "Cloud Scheduler cron for start (UTC), e.g. 30 3 * * *"
  default     = "30 3 * * *"
}

variable "schedule_stop_cron" {
  type        = string
  description = "Cloud Scheduler cron for stop (UTC), e.g. 5 6 * * *"
  default     = "5 6 * * *"
}

variable "schedule_timezone" {
  type    = string
  default = "UTC"
}

variable "bunny_library_id" {
  type        = string
  description = "Bunny Stream Video library ID (same as Ingress portal BUNNY_LIBRARY_ID)"
  default     = ""
}

variable "bunny_api_key" {
  type        = string
  sensitive   = true
  description = "Bunny Stream API Key (not read-only; same as Ingress portal BUNNY_API_KEY)"
  default     = ""
}

variable "bunny_cdn_hostname" {
  type        = string
  description = "Optional Bunny Stream CDN hostname (e.g. vz-xxx.b-cdn.net)"
  default     = ""
}
