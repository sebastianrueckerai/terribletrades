locals {
  reddit_strategy_path       = "${path.module}/../../apps/reddit-strategy"
  reddit_strategy_source_py  = "${local.reddit_strategy_path}/src/strategy_worker.py"
  reddit_health_check_py     = "${local.reddit_strategy_path}/src/health_check.py"
  reddit_strategy_reqs       = "${local.reddit_strategy_path}/requirements.txt"
  reddit_strategy_prompt_txt = "${local.reddit_strategy_path}/src/prompt.txt"
}

resource "kubernetes_config_map" "reddit_strategy_source" {
  metadata {
    name      = "reddit-strategy-source"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    "strategy_worker.py" = file(local.reddit_strategy_source_py)
    "health_check.py"    = file(local.reddit_health_check_py)
    "requirements.txt"   = file(local.reddit_strategy_reqs)
  }
}

resource "kubernetes_config_map" "reddit_strategy_prompt" {
  metadata {
    name      = "reddit-strategy-prompt"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    "prompt.txt" = file(local.reddit_strategy_prompt_txt)
  }
}

resource "kubernetes_secret" "groq_api_key" {
  metadata {
    name      = "groq-api-key"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    GROQ_API_KEY = var.groq_api_key
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "reddit_strategy" {
  metadata {
    name      = "reddit-strategy"
    namespace = kubernetes_namespace.trading.metadata[0].name
    labels = {
      app = "reddit-strategy"
    }
    annotations = {
      "checksum/source" = filesha256(local.reddit_strategy_source_py)
      "checksum/health" = filesha256(local.reddit_health_check_py)
      "checksum/reqs"   = filesha256(local.reddit_strategy_reqs)
      "checksum/prompt" = filesha256(local.reddit_strategy_prompt_txt)
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "reddit-strategy"
      }
    }

    template {
      metadata {
        labels = {
          app = "reddit-strategy"
        }
        annotations = {
          "checksum/source" = filesha256(local.reddit_strategy_source_py)
          "checksum/health" = filesha256(local.reddit_health_check_py)
          "checksum/reqs"   = filesha256(local.reddit_strategy_reqs)
          "checksum/prompt" = filesha256(local.reddit_strategy_prompt_txt)
        }
      }

      spec {
        container {
          name  = "reddit-strategy"
          image = "python:3.12-slim"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              echo "Preparing runtime..." && \
              mkdir -p /app && \
              export PYTHONPATH="/source" && \
              cp /prompt/prompt.txt /app/ && \
              pip install --no-cache-dir -r /source/requirements.txt && \
              python /source/strategy_worker.py
            EOT
          ]

          # Add port for health check
          port {
            container_port = 8080
            name           = "health"
          }

          # Add startup probe to give the Python app more time to initialize
          startup_probe {
            http_get {
              path = "/livez"
              port = "health"
            }
            # Check every 5 seconds
            period_seconds = 5
            # Allow up to 60 seconds for startup (12 failures * 5 seconds)
            failure_threshold = 12
          }

          # Liveness probe: Checks if the application is running
          # If this fails, Kubernetes will restart the container
          liveness_probe {
            http_get {
              path = "/livez" # Updated to use the dedicated liveness endpoint
              port = "health"
            }
            # More time for initial startup (Python app needs time to initialize)
            initial_delay_seconds = 40
            period_seconds        = 15
            timeout_seconds       = 5
            # Higher failure threshold to avoid premature restarts
            failure_threshold = 4
          }

          # Readiness probe: Checks if the application is ready to receive traffic
          # If this fails, Kubernetes will not route traffic to the pod
          readiness_probe {
            http_get {
              path = "/readyz" # Updated to use the dedicated readiness endpoint
              port = "health"
            }
            # More reasonable initial delay for Python app startup
            initial_delay_seconds = 20
            period_seconds        = 10
            timeout_seconds       = 3
            success_threshold     = 1
            # Higher failure threshold to handle transient issues
            failure_threshold = 4
          }

          volume_mount {
            name       = "source-code"
            mount_path = "/source"
          }

          volume_mount {
            name       = "prompt-template"
            mount_path = "/prompt"
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
            name  = "GROQ_MODEL_NAME"
            value = var.groq_model_name
          }

          env {
            name = "GROQ_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.groq_api_key.metadata[0].name
                key  = "GROQ_API_KEY"
              }
            }
          }

          env {
            name  = "STREAM"
            value = "reddit-events"
          }

          env {
            name  = "GROUP"
            value = "strategy-group"
          }

          env {
            name = "CONSUMER"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name  = "SIGNAL_STREAM"
            value = "trade-signals"
          }

          env {
            name  = "PROMPT_FILE"
            value = "/app/prompt.txt"
          }

          env {
            name  = "LOG_LEVEL"
            value = "INFO"
          }

          env {
            name  = "CENTRIFUGO_API_URL"
            value = "http://${local.centrifugo_service_name}.${local.centrifugo_namespace}.svc.cluster.local:${local.centrifugo_api_port}/api"
          }

          env {
            name = "CENTRIFUGO_API_KEY"
            value_from {
              secret_key_ref {
                name = "centrifugo-secrets"
                key  = "CENTRIFUGO_API_KEY"
              }
            }
          }

          env {
            name  = "CENTRIFUGO_CHANNEL"
            value = "trading:trade-signals"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "source-code"
          config_map {
            name = kubernetes_config_map.reddit_strategy_source.metadata[0].name
          }
        }

        volume {
          name = "prompt-template"
          config_map {
            name = kubernetes_config_map.reddit_strategy_prompt.metadata[0].name
          }
        }

        volume {
          name = "app-files"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.reddit_strategy_source,
    kubernetes_config_map.reddit_strategy_prompt,
    kubernetes_secret.groq_api_key,
    kubernetes_secret.shared_redis_password,
    helm_release.redis
  ]
}