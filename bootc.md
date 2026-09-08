# Proof of Concept Guide: RHEL 9 Immutable OS (`bootc`) & Automated Quadlet Workload

**Objective:** This document provides a step-by-step engineering recipe to produce a functional Proof of Concept (PoC) for the RHEL 9 immutable architecture. Following this guide will build a bootable, immutable RHEL 9 system (`disk.qcow2`) running an automated Nginx container managed via Podman Quadlet, and demonstrate atomic updates/rollbacks using `bootc`.

---

## 1. Prerequisites & Build Environment

* **Build Host:** A Linux host (RHEL 9, CentOS Stream 9, or Fedora) with `podman` installed and elevated/sudo privileges.
* **Target Environment:** KVM/QEMU, libvirt, VMware, or any local hypervisor to launch a `.qcow2` virtual machine.
* **Registry Access:** Access to a container registry (e.g., Red Hat Quay, GitHub Packages, or AWS ECR) to test remote OS pushes/pulls.

---

## 2. Phase 1: Define the Application Workload (Quadlet)

In RHEL 9 image-mode, workloads are defined declaratively using **Podman Quadlet** files. When systemd boots, it automatically translates Quadlet files into native systemd unit services.

1. Create a local workspace directory on your build machine:
```bash
mkdir -p ~/bootc-poc/files
cd ~/bootc-poc

```


2. Create a file named `files/app-workload.container` to define the container workload:
```ini
[Unit]
Description=Automated Web Server Workload (PoC)
After=network-online.target

[Container]
Image=quay.io/nginx/nginx-unprivileged:latest
PublishPort=8080:8080
AutoUpdate=registry

[Service]
Restart=always

[Install]
WantedBy=multi-user.target

```



---

## 3. Phase 2: Create the Base OS Image Blueprint

Next, construct a `Containerfile` that derives from the official RHEL 9 bootable base image (`rhel-bootc`) and embeds the Quadlet definition directly into the system layer.

1. Create the `Containerfile` in your workspace (`~/bootc-poc/Containerfile`):
```dockerfile
FROM registry.redhat.io/rhel9/rhel-bootc:9.4

# Optional: Pre-install diagnostic or administrative packages into the immutable OS
RUN dnf -y install net-tools iputils && dnf clean all

# Embed the Quadlet definition so systemd starts it on boot
COPY files/app-workload.container /usr/share/containers/systemd/app-workload.container

# Set a default root password for local console debugging during PoC
RUN echo "root:RedHatPoC2026!" | chpasswd

```


2. Build the OS container image locally using Podman:
```bash
podman build -t quay.io/your-org/rhel9-bootc-poc:v1.0.0 .

```


3. Push the image to your accessible container registry (required for day-2 atomic updates):
```bash
podman push quay.io/your-org/rhel9-bootc-poc:v1.0.0

```



---

## 4. Phase 3: Convert the OS Container into a Bootable VM Disk

To boot the system as a Virtual Machine, convert the containerized OS image into a virtual disk (`.qcow2`) using Red Hat’s `bootc-image-builder`.

1. Run `bootc-image-builder` in a privileged Podman container:
```bash
mkdir -p ./output

sudo podman run --rm -it --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  registry.redhat.io/rhel9/bootc-image-builder:latest \
  --type qcow2 \
  quay.io/your-org/rhel9-bootc-poc:v1.0.0

```


*(This outputs a bootable `disk.qcow2` file inside your `./output/` directory).*

---

## 5. Phase 4: Boot VM & Validate Workload Execution

1. **Launch the VM:** Import `./output/qcow2/disk.qcow2` into KVM/virt-manager, VirtualBox, or your preferred hypervisor and power it on.
2. **Verify Automatic Workload Execution:**
* Allow ~30 seconds for the node to complete its initial boot sequence.
* Run a `curl` request against the running node's IP:
```bash
curl http://<VM_IP_ADDRESS>:8080

```


* **Result:** You will receive the standard Nginx welcome HTML. The containerized application started automatically via systemd without manual SSH interaction.



---

## 6. Phase 5: Demonstrate Atomic OS Updates & Rollback

This phase proves the zero-drift update architecture and recovery capabilities.

### Step 5.1: Build an Updated Version (v1.1.0)

1. On your build machine, update your `Containerfile` to include an extra utility (e.g., `RUN dnf -y install htop && dnf clean all`).
2. Build and push `v1.1.0` to the registry:
```bash
podman build -t quay.io/your-org/rhel9-bootc-poc:v1.1.0 .
podman push quay.io/your-org/rhel9-bootc-poc:v1.1.0

```



### Step 5.2: Apply the Atomic Update

1. SSH into the target PoC Virtual Machine as `root`.
2. Re-point the host system to the newly built image version:
```bash
bootc switch quay.io/your-org/rhel9-bootc-poc:v1.1.0

```


3. Reboot the machine to activate the updated operating system root:
```bash
systemctl reboot

```


4. Log back into the VM after reboot and verify that `htop` is now present.

### Step 5.3: Test Instant Rollback

To demonstrate recovery from a failed deployment, run a single rollback command on the VM host:

```bash
# Revert the active deployment back to the v1.0.0 image state
bootc rollback

# Reboot into the previous bootloader root
systemctl reboot

```

The VM instantly reverts back to its `v1.0.0` state without leaving behind residual files or configuration drift.