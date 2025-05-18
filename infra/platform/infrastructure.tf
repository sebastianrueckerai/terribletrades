terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.44"
    }
  }
}

resource "hcloud_ssh_key" "default" {
  name       = var.ssh_key_name
  public_key = file(var.ssh_pub_path)
}

resource "hcloud_network" "private" {
  name     = "k3s-net"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "subnet" {
  network_id   = hcloud_network.private.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.0.0/24"
}

resource "hcloud_server" "vm" {
  for_each    = var.nodes
  name        = each.key
  server_type = "cx22"
  image       = "ubuntu-22.04"
  location    = var.datacenter
  ssh_keys    = [hcloud_ssh_key.default.id]

  network {
    network_id = hcloud_network.private.id
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_priv_path)
    host        = self.ipv4_address
  }

  depends_on = [hcloud_network_subnet.subnet]
}