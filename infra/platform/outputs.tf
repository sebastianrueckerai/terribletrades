output "public_ips" {
  value = {
    for name, srv in hcloud_server.vm :
    name => srv.ipv4_address
  }
}

output "private_ips" {
  value = {
    for name, srv in hcloud_server.vm :
    name => one(srv.network).ip # one() fails if >1 block => safe
  }
}
output "master_nodes" {
  value = local.master_nodes
}

output "worker_nodes" {
  value = local.worker_nodes
}

output "first_master" {
  value = local.first_master
}

output "redis_password" {
  value     = "redisSecurePass123"
  sensitive = true
}

output "redis_host" {
  value = "redis-master.default.svc.cluster.local"
}

output "k3s_master_ip" {
  description = "IP address of the first K3s master node"
  value       = hcloud_server.vm[local.first_master].ipv4_address
}

output "website_floating_ip" {
  value       = hcloud_floating_ip.website_ip.ip_address
  description = "Floating IP address for the website domain"
}