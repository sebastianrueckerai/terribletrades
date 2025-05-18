provider "hcloud" {
  token = var.hcloud_token
}

provider "kubernetes" {
  config_path = "${path.module}/kubeconfig.yaml"
}

provider "helm" {
  kubernetes {
    host = "https://${hcloud_server.vm[local.first_master].ipv4_address}:6443"

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "${path.module}/kubectl-remote.sh"
      args        = ["get", "pods"] # This will be ignored but is required
    }
  }
}