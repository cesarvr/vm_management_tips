# Practical RHEL 9 Security Hardening

Automated security hardening for **RHEL 9** hosts using a containerized Ansible execution environment powered by Podman and the official [ansible-lockdown (rhel9_stig)](https://galaxy.ansible.com/ui/standalone/roles/ansible-lockdown/rhel9_stig/documentation/) role. This example is meant to be use as a starting point to automate RHEL 9.xx VM hardening. 

This approach provides a portable, zero-dependency hardening runner ideal for integration into **Packer** image builds, CI/CD pipelines, or bare-metal provisioning scripts.


---

## Prerequisites

* **OS:** RHEL 9.x host
* **Container Engine:** Podman installed (`sudo dnf install -y podman`)
* **Privileges:** Root or `sudo` access on the host machine

---

## How It Works

1. A lightweight **Ansible 2.16** environment runs inside an isolated Podman container.
2. The host filesystem or SSH connection is mounted into the container.
3. The `ansible-lockdown/rhel9_stig` playbook executes DISA STIG / CIS baseline mitigations against the targeted host.

---

## Quick Start

### 1. Get The Ansible Image

```bash
    podman login registry.redhat.io
    podman pull registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9:2.16
``` 

### 2. Change Inventory File  

By default in this example is pointing to the local, if you need change it to remote: 

```properties
localhost ansible_connection=ssh ansible_host=127.0.0.1 ansible_user=admin
```

### 3. Run The Playbook

```sh
sh run.sh 
```
> It will ask for the ADMIN password for the VM were is going to execute the tasks. 

Now sit back and take a coffe. 






