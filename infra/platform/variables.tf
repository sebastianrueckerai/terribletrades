variable "datacenter" {
  type        = string
  description = "Hetzner datacenter location"
  default     = "fsn1"
}

variable "ssh_priv_path" {
  type        = string
  description = "Path to local private SSH key"
}

variable "hcloud_token" {
  type        = string
  description = "Hetzner API token"
  sensitive   = true
}

variable "ssh_key_name" {
  type        = string
  description = "Name of SSH key in Hetzner"
}

variable "ssh_pub_path" {
  type        = string
  description = "Path to local public SSH key"
}

variable "nodes" {
  # name => role
  type = map(string)
  default = {
    "master01" = "master"
    "worker01" = "worker"
    "worker02" = "worker"
  }
}

variable "force_kubeconfig_refresh" {
  description = "Set to a new value to force refresh of kubeconfig"
  type        = string
  default     = "0"
}