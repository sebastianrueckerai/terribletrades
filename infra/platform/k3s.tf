locals {
  master_nodes = {
    for k, v in var.nodes : k => v if v == "master"
  }
  worker_nodes = {
    for k, v in var.nodes : k => v if v == "worker"
  }
  first_master = keys(local.master_nodes)[0]
  secondary_masters = {
    for k, v in local.master_nodes : k => v if k != local.first_master
  }
}

# -------------------------
# Primary Master
# -------------------------
resource "null_resource" "install_master_primary" {
  depends_on = [hcloud_server.vm]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_priv_path)
    host        = hcloud_server.vm[local.first_master].ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      "echo '[INSTALL] Starting K3s server on ${local.first_master}'",
      "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644 --tls-san=${hcloud_server.vm[local.first_master].ipv4_address}' sh -",
      "systemctl is-active k3s || journalctl -u k3s --no-pager",
      "mkdir -p /root/.kube",
      "cp /etc/rancher/k3s/k3s.yaml /root/.kube/config",
      "sed -i 's/127.0.0.1/${hcloud_server.vm[local.first_master].ipv4_address}/g' /root/.kube/config",
      "cp /var/lib/rancher/k3s/server/node-token /tmp/k3s_token",
      "chmod 644 /tmp/k3s_token",
      "echo '[DEBUG] Dumping token from /tmp/k3s_token:'",
      "cat /tmp/k3s_token || echo '[ERROR] Token missing!'",
      "ls -l /tmp/k3s_token || true",
      "sha256sum /tmp/k3s_token || true"
    ]
  }
}

# -------------------------
# Fetch kubeconfig from first master
# -------------------------
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [null_resource.install_master_primary]

  provisioner "local-exec" {
    command = <<EOT
    scp -o StrictHostKeyChecking=no -i ${var.ssh_priv_path} root@${hcloud_server.vm[local.first_master].ipv4_address}:/root/.kube/config ./kubeconfig.yaml
    chmod 600 ./kubeconfig.yaml
    EOT
  }

  triggers = {
    # Only run when these actually change
    master_ip   = hcloud_server.vm[local.first_master].ipv4_address
    master_id   = hcloud_server.vm[local.first_master].id
    k3s_install = md5(join(",", null_resource.install_master_primary.*.id))
    # Optional - run if you explicitly set this variable
    force_refresh = var.force_kubeconfig_refresh
  }
}

# -------------------------
# Joining Masters
# -------------------------
resource "null_resource" "install_master_joining" {
  for_each   = local.secondary_masters
  depends_on = [null_resource.install_master_primary]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_priv_path)
    host        = hcloud_server.vm[each.key].ipv4_address
  }

  # First get the token from the primary master
  provisioner "remote-exec" {
    inline = [
      "echo '[SETUP] Setting up secondary master node ${each.key}'",
      "mkdir -p /tmp/k3s"
    ]
  }

  # Copy the token from the master to the secondary master
  provisioner "local-exec" {
    command = <<EOT
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_priv_path} root@${hcloud_server.vm[local.first_master].ipv4_address} \
      "cat /tmp/k3s_token" | \
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_priv_path} root@${hcloud_server.vm[each.key].ipv4_address} \
      "cat > /tmp/k3s/node-token"
    EOT
  }

  # Install K3s server using the token
  provisioner "remote-exec" {
    inline = [
      "echo '[INSTALL] Starting K3s server on ${each.key}'",
      "TOKEN=$(cat /tmp/k3s/node-token)",
      "echo '[DEBUG] Token retrieved, length:' $(echo $TOKEN | wc -c)",
      "curl -sfL https://get.k3s.io | K3S_URL=https://${hcloud_server.vm[local.first_master].ipv4_address}:6443 K3S_TOKEN=$TOKEN INSTALL_K3S_EXEC='server' sh -",
      "systemctl is-active k3s || journalctl -u k3s --no-pager",
      "echo '[SUCCESS] K3s server installed on ${each.key}'"
    ]
  }
}

# -------------------------
# Workers
# -------------------------
resource "null_resource" "install_worker" {
  for_each   = local.worker_nodes
  depends_on = [null_resource.install_master_primary]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_priv_path)
    host        = hcloud_server.vm[each.key].ipv4_address
  }

  # First get the token from the master
  provisioner "remote-exec" {
    inline = [
      "echo '[SETUP] Setting up worker node ${each.key}'",
      "mkdir -p /tmp/k3s"
    ]
  }

  # Copy the token from the master to the worker
  provisioner "local-exec" {
    command = <<EOT
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_priv_path} root@${hcloud_server.vm[local.first_master].ipv4_address} \
      "cat /tmp/k3s_token" | \
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_priv_path} root@${hcloud_server.vm[each.key].ipv4_address} \
      "cat > /tmp/k3s/node-token"
    EOT
  }

  # Install K3s agent using the token
  provisioner "remote-exec" {
    inline = [
      "echo '[INSTALL] Starting K3s agent on ${each.key}'",
      "TOKEN=$(cat /tmp/k3s/node-token)",
      "echo '[DEBUG] Token retrieved, length:' $(echo $TOKEN | wc -c)",
      "curl -sfL https://get.k3s.io | K3S_URL=https://${hcloud_server.vm[local.first_master].ipv4_address}:6443 K3S_TOKEN=$TOKEN sh -",
      "systemctl is-active k3s-agent || journalctl -u k3s-agent --no-pager",
      "echo '[SUCCESS] K3s agent installed on ${each.key}'"
    ]
  }
}