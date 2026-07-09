output "control_public_ip" {
  value = google_compute_address.control.address
}

output "jvb_public_ip" {
  value = google_compute_address.jvb.address
}

output "control_private_ip" {
  value = google_compute_instance.control.network_interface[0].network_ip
}

output "jvb_private_ip" {
  value = google_compute_instance.jvb.network_interface[0].network_ip
}

output "jibri_names" {
  value = [for i in google_compute_instance.jibri : i.name]
}

output "jibri_private_ips" {
  value = [for i in google_compute_instance.jibri : i.network_interface[0].network_ip]
}

output "domain" {
  value = var.domain
}

output "meet_url" {
  value = "https://${var.domain}"
}

output "secrets_file" {
  value = "${path.module}/generated/outputs.json"
}
