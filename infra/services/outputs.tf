output "centrifugo_service_name" {
  value = "centrifugo.${kubernetes_namespace.trading.metadata[0].name}.svc.cluster.local"
}
