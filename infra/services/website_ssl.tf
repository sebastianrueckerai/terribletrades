resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.17.2"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "null_resource" "apply_cluster_issuer" {
  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    command = <<-EOT
      # Check if ClusterIssuer exists
      if ! kubectl get clusterissuer letsencrypt-prod &>/dev/null; then
        # Create ClusterIssuer if it doesn't exist
        cat <<ISSUER | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${var.email_address}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
ISSUER
        echo "ClusterIssuer created"
      else
        echo "ClusterIssuer already exists"
      fi
    EOT
  }
}

# Make sure Traefik is running (in case it was disabled)
resource "null_resource" "ensure_traefik_running" {
  depends_on = [null_resource.apply_cluster_issuer]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${var.kubeconfig_path}
      kubectl -n kube-system scale deployment traefik --replicas=1
      # Wait for Traefik to be ready
      kubectl -n kube-system wait --for=condition=Available deployment/traefik --timeout=60s
    EOT
  }
}

# Create Ingress for the website with TLS
resource "kubernetes_ingress_v1" "website" {
  depends_on = [kubernetes_service.website, null_resource.apply_cluster_issuer]

  metadata {
    name      = "website-ingress"
    namespace = "website"
    annotations = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-prod"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = [var.domain_name, "www.${var.domain_name}"]
      secret_name = "website-tls"
    }

    rule {
      host = var.domain_name
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "website"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "www.${var.domain_name}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "website"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "centrifugo" {
  depends_on = [null_resource.apply_cluster_issuer]

  metadata {
    name      = "centrifugo-ingress"
    namespace = "trading"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"

      # Critical WebSocket annotations for Traefik
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web,websecure"
      "traefik.ingress.kubernetes.io/router.middlewares" = "trading-stripprefix@kubernetescrd"

      # Make sure this matches the Centrifugo websocket path
      "traefik.ingress.kubernetes.io/websocket"         = "true"
      "traefik.ingress.kubernetes.io/service.buffering" = "false"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts       = [var.domain_name]
      secret_name = "centrifugo-tls"
    }

    rule {
      host = var.domain_name
      http {
        path {
          path      = "/api/centrifugo" # No trailing slash
          path_type = "Prefix"
          backend {
            service {
              name = "centrifugo"
              port {
                number = 8000
              }
            }
          }
        }
      }
    }
  }
}

# Create the middleware for path stripping
resource "kubernetes_manifest" "strip_prefix_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "stripprefix"
      namespace = "trading"
    }
    spec = {
      stripPrefix = {
        prefixes = ["/api/centrifugo"]
      }
    }
  }
}