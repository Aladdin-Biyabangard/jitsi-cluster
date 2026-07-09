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

variable "bunny_storage_zone" {
  type      = string
  sensitive = true
  default   = ""
}

variable "bunny_storage_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "bunny_storage_region" {
  type    = string
  default = "de"
}

variable "bunny_cdn_hostname" {
  type    = string
  default = ""
}

variable "bunny_upload_path" {
  type    = string
  default = "recordings"
}
