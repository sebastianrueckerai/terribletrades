locals {
  reddit_poller_main = "${path.module}/../../apps/reddit-poller/src/main.go"
  reddit_poller_mod  = "${path.module}/../../apps/reddit-poller/go.mod"
  reddit_poller_sum  = "${path.module}/../../apps/reddit-poller/go.sum"
}

resource "kubernetes_config_map" "reddit_poller_source" {
  metadata {
    name      = "reddit-poller-source"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    "main.go" = file(local.reddit_poller_main)
    "go.mod"  = file(local.reddit_poller_mod)
    "go.sum"  = file(local.reddit_poller_sum)
  }
}

resource "kubernetes_secret" "reddit_poller_secrets" {
  metadata {
    name      = "reddit-poller-secrets"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    REDDIT_CLIENT_ID     = var.reddit_client_id
    REDDIT_CLIENT_SECRET = var.reddit_client_secret
    REDDIT_USERNAME      = var.reddit_username
    REDDIT_PASSWORD      = var.reddit_password
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "reddit_poller" {
  metadata {
    name      = "reddit-poller"
    namespace = kubernetes_namespace.trading.metadata[0].name
    labels = {
      app = "reddit-poller"
    }
    annotations = {
      "checksum/main.go" = filesha256(local.reddit_poller_main)
      "checksum/go.mod"  = filesha256(local.reddit_poller_mod)
      "checksum/go.sum"  = filesha256(local.reddit_poller_sum)
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "reddit-poller"
      }
    }

    template {
      metadata {
        labels = {
          app = "reddit-poller"
        }
        annotations = {
          "checksum/main.go" = filesha256(local.reddit_poller_main)
          "checksum/go.mod"  = filesha256(local.reddit_poller_mod)
          "checksum/go.sum"  = filesha256(local.reddit_poller_sum)
        }
      }

      spec {
        init_container {
          name  = "builder"
          image = "golang:1.22"

          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            set -e  # Exit immediately if a command exits with a non-zero status
            
            echo "Starting build process..."
            mkdir -p /app
            
            echo "Copying source files..."
            cp /source/* /app/ || { echo "ERROR: Failed to copy source files"; exit 1; }
            ls -la /app  # List files to verify copy
            
            cd /app
            
            echo "Downloading Go modules..."
            go mod download || { echo "ERROR: Failed to download Go modules"; ls -la; cat go.mod; exit 1; }
            
            echo "Building application..."
            CGO_ENABLED=0 GOOS=linux go build -o reddit-poller . || { echo "ERROR: Build failed"; exit 1; }
            ls -la  # Verify binary was created
            
            echo "Moving binary to shared volume..."
            mkdir -p /output
            cp reddit-poller /output/ || { echo "ERROR: Failed to copy binary"; exit 1; }
            ls -la /output  # Verify binary was moved
            
            echo "Build complete!"
          EOT
          ]

          volume_mount {
            name       = "source-code"
            mount_path = "/source"
          }

          volume_mount {
            name       = "binary-output"
            mount_path = "/output"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }

        container {
          name  = "reddit-poller"
          image = "alpine:latest"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            if [ ! -f /app/reddit-poller ]; then
              echo "ERROR: Binary not found at /app/reddit-poller"
              echo "Contents of /app directory:"
              ls -la /app
              echo "Contents of volumes:"
              ls -la /
              exit 1
            fi
            
            echo "Binary found, setting executable permission"
            chmod +x /app/reddit-poller
            
            echo "Starting reddit-poller"
            /app/reddit-poller
            EOT
          ]

          volume_mount {
            name       = "binary-output"
            mount_path = "/app"
          }
          # Add port for health check
          port {
            container_port = 8080
            name           = "health"
          }

          # Add liveness probe
          liveness_probe {
            http_get {
              path = "/livez"
              port = "health"
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            timeout_seconds       = 5
            failure_threshold     = 4
          }

          # Add readiness probe
          readiness_probe {
            http_get {
              path = "/readyz"
              port = "health"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
            success_threshold     = 1
            failure_threshold     = 4
          }

          # Add startup probe
          startup_probe {
            http_get {
              path = "/livez"
              port = "health"
            }
            period_seconds    = 5
            failure_threshold = 12 # Allow up to 60 seconds for startup
          }

          env {
            name  = "SUBREDDITS"
            value = var.subreddits
          }

          env {
            name  = "REDDIT_APP_NAME"
            value = var.reddit_app_name
          }

          env {
            name  = "HEALTH_PORT"
            value = "8080"
          }

          env {
            name  = "REDIS_ADDR"
            value = "${local.redis_service_address}:6379"
          }

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = "shared-redis-password"
                key  = "redis_password"
              }
            }
          }

          env {
            name  = "DEBUG"
            value = "true"
          }

          env {
            name = "REDDIT_CLIENT_ID"
            value_from {
              secret_key_ref {
                name = "reddit-poller-secrets"
                key  = "REDDIT_CLIENT_ID"
              }
            }
          }

          env {
            name = "REDDIT_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = "reddit-poller-secrets"
                key  = "REDDIT_CLIENT_SECRET"
              }
            }
          }

          env {
            name = "REDDIT_USERNAME"
            value_from {
              secret_key_ref {
                name = "reddit-poller-secrets"
                key  = "REDDIT_USERNAME"
              }
            }
          }

          env {
            name = "REDDIT_PASSWORD"
            value_from {
              secret_key_ref {
                name = "reddit-poller-secrets"
                key  = "REDDIT_PASSWORD"
              }
            }
          }

          resources {
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "source-code"
          config_map {
            name = kubernetes_config_map.reddit_poller_source.metadata[0].name
          }
        }

        volume {
          name = "binary-output"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.reddit_poller_source,
    kubernetes_secret.reddit_poller_secrets,
    kubernetes_secret.shared_redis_password,
    helm_release.redis
  ]
}
