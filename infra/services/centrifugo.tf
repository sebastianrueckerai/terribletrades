locals {
  centrifugo_service_name = "centrifugo"
  centrifugo_namespace    = "trading"
  centrifugo_api_port     = 9000
  centrifugo_ws_port      = 8000
  centrifugo_grpc_port    = 10000
}

resource "kubernetes_secret" "centrifugo_config" {
  metadata {
    name      = "centrifugo-secrets"
    namespace = kubernetes_namespace.trading.metadata[0].name
  }

  data = {
    CENTRIFUGO_TOKEN_HMAC_SECRET = var.centrifugo_token_hmac_secret
    CENTRIFUGO_API_KEY           = var.centrifugo_api_key
    CENTRIFUGO_ADMIN_PASSWORD    = var.centrifugo_admin_password
    CENTRIFUGO_ADMIN_SECRET      = var.centrifugo_admin_secret
  }

  type = "Opaque"
}

resource "helm_release" "centrifugo" {
  name       = local.centrifugo_service_name
  namespace  = kubernetes_namespace.trading.metadata[0].name
  repository = "https://centrifugal.github.io/helm-charts"
  chart      = "centrifugo"
  version    = "12.3.0"

  values = [
    templatefile("${path.module}/centrifugo-values.yaml", {
      CENTRIFUGO_TOKEN_HMAC_SECRET = var.centrifugo_token_hmac_secret
      CENTRIFUGO_API_KEY           = var.centrifugo_api_key
      CENTRIFUGO_ADMIN_PASSWORD    = var.centrifugo_admin_password
      CENTRIFUGO_ADMIN_SECRET      = var.centrifugo_admin_secret
      CENTRIFUGO_API_PORT          = local.centrifugo_api_port
      CENTRIFUGO_WS_PORT           = local.centrifugo_ws_port
    })
  ]

  depends_on = [
    kubernetes_namespace.trading,
    kubernetes_secret.centrifugo_config
  ]
}