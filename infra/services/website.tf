# -------------------------
# Namespace
# -------------------------

resource "kubernetes_namespace" "website" {
  metadata {
    name = "website"
  }
}

# -------------------------
# Frontend Files ConfigMap with Pre-built Zip
# -------------------------

locals {
  # Correct paths to the files in the fe directory
  zip_file_path      = "${path.module}/../../fe/frontend.zip"
  checksum_file_path = "${path.module}/../../fe/frontend.zip.sha256"

  # Read the zip checksum from the file (created in Phase 1)
  zip_checksum = fileexists(local.checksum_file_path) ? file(local.checksum_file_path) : "none"
}

resource "kubernetes_config_map" "website_zip" {
  metadata {
    name      = "website-zip"
    namespace = kubernetes_namespace.website.metadata[0].name
    annotations = {
      # Use the checksum from Phase 1
      "checksum/zip" = local.zip_checksum
    }
  }

  binary_data = {
    "frontend.zip" = filebase64(local.zip_file_path)
  }
}

# -------------------------
# Config Maps for Runtime Config & Nginx
# -------------------------

resource "kubernetes_config_map" "runtime_config" {
  metadata {
    name      = "website-runtime-config"
    namespace = kubernetes_namespace.website.metadata[0].name
  }

  data = {
    "config.js" = <<-EOT
      window.CONFIG = {
        centrifugoUrl: "wss://${var.domain_name}/api/centrifugo/connection/websocket",
        centrifugoToken: "${var.centrifugo_token}",
        centrifugoChannel: "trading:trade-signals",
        apiUrl: "https://${var.domain_name}/api",
        environment: "production"
      };
    EOT
  }
}

resource "kubernetes_config_map" "nginx_config" {
  metadata {
    name      = "website-nginx-config"
    namespace = kubernetes_namespace.website.metadata[0].name
  }

  data = {
    "default.conf" = <<-EOT
      server {
        listen 80;
        root /usr/share/nginx/html;
        index index.html;
        
        # SPA routing
        location / {
          try_files $uri $uri/ /index.html;
        }
        
        # Set proper cache headers for static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
          expires 30d;
          add_header Cache-Control "public, no-transform";
        }
      }
    EOT
  }
}

# -------------------------
# Deployment & Service
# -------------------------

resource "kubernetes_deployment" "website" {
  metadata {
    name      = "website"
    namespace = kubernetes_namespace.website.metadata[0].name
    labels = {
      app = "website"
    }
    annotations = {
      # Force redeployment when zip file changes
      "checksum/zip" = local.zip_checksum
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "website"
      }
    }

    template {
      metadata {
        labels = {
          app = "website"
        }
        annotations = {
          # Force pod recreation when frontend zip changes
          "checksum/zip" = local.zip_checksum
        }
      }

      spec {
        # Init container to extract zip file
        init_container {
          name  = "extract-frontend"
          image = "busybox:latest"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              echo "Extracting frontend zip archive..." && \
              mkdir -p /usr/share/nginx/html && \
              unzip -o /website-zip/frontend.zip -d /usr/share/nginx/html && \
              chmod -R 755 /usr/share/nginx/html && \
              echo "Frontend files extracted successfully."
            EOT
          ]

          volume_mount {
            name       = "website-zip"
            mount_path = "/website-zip"
          }

          volume_mount {
            name       = "html-dir"
            mount_path = "/usr/share/nginx/html"
          }
        }

        container {
          name  = "website"
          image = "nginx:alpine"

          port {
            container_port = 80
          }

          # Mount the shared html volume that was prepared by the init container
          volume_mount {
            name       = "html-dir"
            mount_path = "/usr/share/nginx/html"
          }

          # Mount nginx config
          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/conf.d/default.conf"
            sub_path   = "default.conf"
          }

          # Mount runtime config
          volume_mount {
            name       = "runtime-config"
            mount_path = "/usr/share/nginx/html/config.js"
            sub_path   = "config.js"
          }

          # Add readiness probe
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 5
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

        # Volumes
        volume {
          name = "website-zip"
          config_map {
            name = kubernetes_config_map.website_zip.metadata[0].name
          }
        }

        volume {
          name = "html-dir"
          empty_dir {} # Shared between init container and main container
        }

        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.nginx_config.metadata[0].name
          }
        }

        volume {
          name = "runtime-config"
          config_map {
            name = kubernetes_config_map.runtime_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Service for the website
resource "kubernetes_service" "website" {
  metadata {
    name      = "website"
    namespace = kubernetes_namespace.website.metadata[0].name
  }

  spec {
    selector = {
      app = "website"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}