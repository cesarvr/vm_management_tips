## WSL With Same Network Interface

By default, **WSL2** operates on a Hyper-V Virtual Ethernet adapter with **NAT (Network Address Translation)**. This assigns Linux a virtual private IP (often in the `172.x.x.x` or `10.x.x.x` range) that differs from your Windows host IP.

Corporate firewalls, VPNs, and Endpoint Detection tools (like Zscaler, Palo Alto GlobalProtect, or CrowdStrike) often inspect outgoing network packets, detect an unknown IP subnet that isn't bound to your corporate-managed identity, and block the connection.

To resolve this issue, use the following methods ordered from the most effective fix to alternative options.

---

### Solution 1: Enable Mirrored Networking Mode (Recommended)

Microsoft added **Mirrored Networking Mode** to WSL2. Instead of running WSL behind its own NAT router with its own separate IP, Mirrored Mode forces WSL to share and mirror your Windows host's exact network interfaces and IP address.

1. Open PowerShell in Windows and shut down WSL completely:
```powershell
wsl --shutdown

```


2. Open or create your global `.wslconfig` file by running:
```powershell
notepad $env:USERPROFILE\.wslconfig

```


3. Add the following lines to the file:
```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true

```


* **`networkingMode=mirrored`**: Shares your host's IP address directly.
* **`dnsTunneling=true`**: Routes DNS requests through Windows to avoid corporate DNS blocks.
* **`autoProxy=true`**: Automatically forwards your Windows corporate HTTP/HTTPS proxy settings into WSL.


4. Save the file and restart WSL in PowerShell:
```powershell
wsl

```



**Verification:** Inside your Linux terminal, run `ip addr` or `curl ifconfig.me`. The output should reflect your host machine's network configuration rather than a isolated virtual subnet.

---

### Solution 2: Revert to WSL 1 (If Mirrored Mode is Unavailable/Blocked)

If your corporate Windows build is locked down or running older Windows builds where Mirrored Mode isn't supported, you can switch the Linux distribution to **WSL 1**.

Unlike WSL 2 (which uses a Hyper-V Virtual Machine with its own virtual NIC), WSL 1 shares the host Windows networking stack directly.

1. List your installed distros in PowerShell:
```powershell
wsl --list --verbose

```


2. Convert your distribution to WSL 1:
```powershell
wsl --set-version <DistroName> 1

```


*(Replace `<DistroName>` with your distribution, e.g., `Ubuntu`)*

---

### Solution 3: Add a Firewall Rule on Windows (If traffic is blocked locally)

If the block is happening at the local Windows Defender Firewall / Hyper-V Firewall level rather than the corporate network perimeter, allow the WSL virtual switch traffic through:

Run **PowerShell as Administrator**:

```powershell
New-NetFirewallRule -DisplayName "WSL Corporate Traffic" -Direction Inbound -InterfaceAlias "vEthernet (WSL)" -Action Allow

```
