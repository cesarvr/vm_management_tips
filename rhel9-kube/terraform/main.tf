terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# 1. Define the Isolated NAT Network over Host Wi-Fi
resource "libvirt_network" "k8s_net" {
  name      = "k8s-net"
  mode      = "nat"
  domain    = "k8s.local"
  addresses = ["192.168.100.0/24"]
  autostart = true

  dhcp {
    enabled = true
  }
}

# 2. Define the Base OS Volume
resource "libvirt_volume" "rhel9_base" {
  name   = "rhel9_base.qcow2"
  pool   = "default"
  source = "/var/lib/libvirt/images/base/rhel9.qcow2"
  format = "qcow2"
}

# Define VM Node Configs (1 Control Plane, 2 Workers)
locals {
  nodes = {
    "k8s-master"  = "192.168.100.10"
    "k8s-worker1" = "192.168.100.11"
    "k8s-worker2" = "192.168.100.12"
  }
}

# 3. Create Copy-on-Write Disks for Each VM
resource "libvirt_volume" "node_disk" {
  for_each       = local.nodes
  name           = "${each.key}-disk.qcow2"
  base_volume_id = libvirt_volume.rhel9_base.id
  pool           = "default"
  size           = 21474836480 # 20 GB
}

# 4. Automate Static IP, Hostname, and SSH Configuration
resource "libvirt_cloudinit_disk" "commoninit" {
  for_each  = local.nodes
  name      = "${each.key}-cloudinit.iso"
  pool      = "default"
  user_data = <<-EOF
    #cloud-config
    hostname: ${each.key}
    fqdn: ${each.key}.k8s.local
    manage_etc_hosts: true
    users:
      - name: root
        ssh_authorized_keys:
          - ${file("~/.ssh/id_rsa.pub")}
    disable_root: false
    ssh_pwauth: true
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses:
          - ${each.value}/24
        gateway4: 192.168.100.1
        nameservers:
          addresses:
            - 1.1.1.1
            - 8.8.8.8
  EOF
}

# 5. Create the Virtual Machines
resource "libvirt_domain" "k8s_node" {
  for_each = local.nodes

  name     = each.key
  memory   = "4096" # 4 GB RAM per node
  vcpu     = 2

  cpu {
    mode = "host-passthrough"
  }

  cloudinit = libvirt_cloudinit_disk.commoninit[each.key].id

  network_interface {
    network_id     = libvirt_network.k8s_net.id
    addresses      = [each.value]
    wait_for_lease = false
  }

  disk {
    volume_id = libvirt_volume.node_disk[each.key].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

output "node_ips" {
  value = { for k, v in local.nodes : k => v }
}
