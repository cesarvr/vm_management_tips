Because your CachyOS host uses **Wi-Fi**, standard bridging won't work due to 802.11 frame restrictions. The ideal setup for a local Kubernetes cluster is a **dedicated NAT virtual network** inside `libvirt`.

In this setup:

* The 3 RHEL 9 VMs sit on an isolated virtual subnet (e.g., `192.168.100.0/24`) with permanent static IPs.
* They talk to each other inside RAM at near bare-metal speed.
* They route out to the internet through your CachyOS host's Wi-Fi card.

---

### Step 1: Install Required Tools on CachyOS

Open a terminal and install Terraform, libvirt, and cloud-init tools:

```bash
sudo pacman -S terraform libvirt qemu-desktop virt-manager cdrkit
sudo systemctl enable --now libvirtd

```

* **Verification:** Run `virsh uri` to confirm `libvirtd` is running. It should return `qemu:///system`.

---

### Step 2: Download the RHEL 9 KVM Cloud Image

Download the official RHEL 9 KVM image (or AlmaLinux/Rocky Linux 9 if you don't have an active Red Hat subscription, as they use the exact same binaries):

```bash
sudo mkdir -p /var/lib/libvirt/images/base
# Replace with your actual RHEL 9 KVM qcow2 image path
sudo cp rhel-9.6-x86_64-kvm.qcow2 /var/lib/libvirt/images/base/rhel9.qcow2

```

---

### Step 3: Write the `main.tf` File

Create a new directory (e.g., `mkdir k8s-infra && cd k8s-infra`) and save the following code as `main.tf`.

```hcl
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

  cloudinit = libvirt_cloudinit_disk.commoninit[each.key].id

  network_interface {
    network_id     = libvirt_network.k8s_net.id
    addresses      = [each.value]
    wait_for_lease = true
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

```

---

### Step 4: Deploy the Cluster with Terraform

1. Ensure you have an SSH key created on your CachyOS host:
```bash
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

```


2. Initialize Terraform and apply the deployment:
```bash
terraform init
terraform apply -auto-approve

```



* **Verification:** Run `virsh list --all` to see your 3 VMs (`k8s-master`, `k8s-worker1`, `k8s-worker2`) in a `running` state.
* **Test SSH Access:** Run `ssh root@192.168.100.10` from your CachyOS terminal to connect directly to the master node without typing a password.

---

### Why This Avoids All "Pain Points"

1. **Wi-Fi Friendly:** Uses `libvirt`'s native `nat` mode. Your Wi-Fi router only sees your CachyOS laptop, but all 3 VMs have individual static IPs on the `192.168.100.x` subnet.
2. **Automated Cloud-Init:** Handles SSH keys, root passwords, static IPs, and hostnames automatically during first boot.
3. **One-Command Teardown:** When you are done testing Kubernetes, running `terraform destroy` completely cleans up all 3 VMs, virtual networks, and storage disks in seconds.

[https://www.youtube.com/watch?v=572FdBQe07E](https://www.youtube.com/watch?v=572FdBQe07E)

This video walks through installing KVM and libvirt on Red Hat Enterprise Linux 9, providing helpful visual context for the underlying KVM/libvirt virtualization architecture managed by Terraform.