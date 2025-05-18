locals {
  inspect_script = "${path.module}/scripts/redis/inspect-redis-streams.sh"
  monitor_script = "${path.module}/scripts/redis/monitor-redis-streams.sh"
}

resource "kubernetes_config_map" "redis_inspection_scripts" {
  metadata {
    name      = "redis-inspection-scripts"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    "inspect-redis-streams.sh" = file(local.inspect_script)
    "monitor-redis-streams.sh" = file(local.monitor_script)
  }
}

resource "kubernetes_pod" "redis_inspector" {
  metadata {
    name      = "redis-inspector"
    namespace = kubernetes_namespace.trading.metadata[0].name
    labels = {
      app = "redis-inspector"
    }
    annotations = {
      "checksum/inspect" = filesha256(local.inspect_script)
      "checksum/monitor" = filesha256(local.monitor_script)
    }
  }

  spec {
    container {
      name  = "redis-inspector"
      image = "redis:latest"

      command = ["/bin/sh", "-c"]
      args = [<<-EOT
        echo '${filesha256(local.inspect_script)}'
        echo '${filesha256(local.monitor_script)}'
        cp /scripts/* /usr/local/bin/
        chmod +x /usr/local/bin/inspect-redis-streams.sh /usr/local/bin/monitor-redis-streams.sh
        echo 'Redis inspector ready! Run: kubectl exec -it redis-inspector -n trading -- /bin/sh'
        sleep infinity
        EOT
      ]
      env {
        name  = "REDIS_HOST"
        value = local.redis_service_address
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

      volume_mount {
        name       = "inspection-scripts"
        mount_path = "/scripts"
      }
    }

    volume {
      name = "inspection-scripts"
      config_map {
        name = kubernetes_config_map.redis_inspection_scripts.metadata[0].name
      }
    }
  }

  depends_on = [
    helm_release.redis
  ]
}
