resource "helm_release" "redis" {
  name      = "redis"
  namespace = kubernetes_namespace.trading.metadata[0].name

  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  version    = "19.6.4"

  values = [
    templatefile("${path.module}/redis-values.yaml", {
      REDIS_PASSWORD = var.redis_password
    })
  ]
}

data "kubernetes_service" "redis_master" {
  metadata {
    name      = "redis-master"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }
  depends_on = [helm_release.redis]
}

# Use the service name with namespace for DNS
locals {
  redis_service_address = "${data.kubernetes_service.redis_master.metadata[0].name}.${data.kubernetes_service.redis_master.metadata[0].namespace}.svc.cluster.local"
}

resource "kubernetes_secret" "shared_redis_password" {
  metadata {
    name      = "shared-redis-password"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    redis_password = var.redis_password
  }

  type = "Opaque"
}