terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.44"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "kubernetes_namespace" "trading" {
  metadata {
    name = "trading"
  }
}

# For remote kubectl access via SSH
resource "local_file" "kubectl_script" {
  filename = "${path.module}/kubectl-remote.sh"
  content  = <<-EOT
    #!/bin/bash
    ssh -o StrictHostKeyChecking=no -i ${var.ssh_priv_path} root@${var.master_ip} kubectl $@
    EOT

  provisioner "local-exec" {
    command = "chmod +x ${path.module}/kubectl-remote.sh"
  }
}