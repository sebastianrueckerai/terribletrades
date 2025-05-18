resource "hcloud_floating_ip" "website_ip" {
  type          = "ipv4"
  name          = "website-ip"
  home_location = var.datacenter
}

resource "hcloud_floating_ip_assignment" "website" {
  floating_ip_id = hcloud_floating_ip.website_ip.id
  server_id      = hcloud_server.vm[local.first_master].id
}

resource "null_resource" "configure_floating_ip" {
  depends_on = [hcloud_floating_ip_assignment.website]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_priv_path)
    host        = hcloud_server.vm[local.first_master].ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      "ip addr add ${hcloud_floating_ip.website_ip.ip_address}/32 dev eth0",
      "echo 'ip addr add ${hcloud_floating_ip.website_ip.ip_address}/32 dev eth0' >> /etc/rc.local",
      "chmod +x /etc/rc.local"
    ]
  }
}

