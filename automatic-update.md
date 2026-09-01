# Automatic Updates Implementation Guide
**Authored by:** Cesar Valdez

<BR>


## 1. Overview & Architecture Strategy

Kerry manages several virtual machines in vSphere that are currently not managed by Azure. Because of this, onboard options for the Azure Automatic Update program are not viable at the moment.

### About Using Cron vs. Systemd Timers

* **Missed Execution Handling (Power Down):** If your system is powered off, down for maintenance, or suspended when the end-of-month cron job triggers, `cron` simply misses it and will not run until the next month. `Systemd Timers` feature built-in persistence (`Persistent=true`). If the system is offline during the scheduled run time, systemd executes the update immediately upon the next boot.
* **Integrated Logging & Dependency Control:** `cron` runs blind and writes output to local mail files or `/dev/null`. Systemd timer services output directly into `journald`, making debugging `dnf` transactions easier via `journalctl -u dnf-automatic-install.service`.
* **Vendor Packaging Standards:** Package utilities provided by Red Hat (such as `dnf-automatic`) ship natively with systemd `.timer` and `.service` unit files rather than cron jobs.

---

## 2. Automatic Updates on Red Hat Enterprise Linux (RHEL 9.x)

To configure automatic end-of-month security updates on RHEL 9.xx without using cron, use `dnf-automatic` combined with a custom systemd timer drop-in override.

### Step 1: Install `dnf-automatic`

Install the official update utility via standard package management:

```bash
sudo dnf install -y dnf-automatic
```

### Step 2: Configure for Security-Only Updates

Edit `dnf-automatic` configuration file:

```bash
sudo nano /etc/dnf/automatic.conf
```

Set the following options under the `[commands]` section:


```toml
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes
```

> (Optional) Add recipient addresses under `[email]` and change `emit_via = email` under `[emitters]` if you want email reports after execution.

### Step 3: Schedule Execution

By default, the timer runs daily. Create a systemd drop-in file to change its schedule to choose a specific day in each month:

* Open a systemd override editor for the installation timer unit:

    ```bash
    sudo systemctl edit dnf-automatic-install.timer
    ```

* Paste the following configuration, which clears the default schedule and triggers on the final calendar day of the month at 02:00 AM:

    ``` toml
    [Timer]
    OnCalendar=
    OnCalendar=*-*-01 02:00:00
    Persistent=true
    ```

   Here is a breakdown of how the `OnCalendar` expression `*-*-~01 02:00:00` works in systemd timers:

##### Understanding the Systemd Timer Expression

The syntax `*-*-~01 02:00:00` uses systemd's **OnCalendar** time format, which follows a general pattern of `Year-Month-Day Hour:Minute:Second`.

##### Field Breakdown

* **`*` (Year):** The first asterisk means "every year".
* **`*` (Month):** The second asterisk means "every month".
* **`01` (Day):** Day of the month.

* Systemd automatically handles different month lengths, correctly targeting the 28th/29th of February, the 30th of April/June/September/November, and the 31st of all other months.


### Step 4: Running & Testing

To enable and start the timer:

```bash
sudo systemctl enable --now dnf-automatic-install.timer
```

Verify:

```bash
sudo systemctl list-timers dnf-automatic-install.timer
```

You should see something like this: 

```bash 
NEXT                        LEFT       LAST PASSED UNIT                            ACTIVATES
Tue 2026-09-01 02:00:00 CEST 4 days left n/a  n/a    dnf-automatic-install.timer     dnf-automatic-install.service
```

If you want to see the logs: 

```sh
sudo journalctl -u dnf-automatic-install.service
```

Typical output:

```sh
-- Logs begin at Mon 2026-08-01 00:00:00 CEST, end at Thu 2026-08-27 13:15:00 CEST. --
Aug 31 02:00:00 server01 systemd[1]: Starting dnf-automatic-install.service - dnf automatic install updates...
Aug 31 02:00:02 server01 dnf-automatic[14205]: Last metadata expiration check: 1:12:04 ago on Thu 27 Aug 2026 12:07:56 PM CEST.
Aug 31 02:00:05 server01 dnf-automatic[14205]: Dependencies resolved.
Aug 31 02:00:05 server01 dnf-automatic[14205]: ================================================================================
Aug 31 02:00:05 server01 dnf-automatic[14205]:  Package               Arch       Version                  Repository      Size
Aug 31 02:00:05 server01 dnf-automatic[14205]: ================================================================================
Aug 31 02:00:05 server01 dnf-automatic[14205]: Upgrading:
Aug 31 02:00:05 server01 dnf-automatic[14205]:  openssl-libs          x86_64     3.0.7-27.el9_4           rhel-9-appstream 2.2 M
Aug 31 02:00:05 server01 dnf-automatic[14205]:  kernel                x86_64     5.14.0-427.28.1.el9_4    rhel-9-baseos    5.2
...
...
```

> We usually check here the logs after the job has run.

## 3. Automatic Updates on SUSE Linux Enterprise Server (SLES 15.5)

### Step 1: Create the Systemd Service Unit

```sh
sudo nano /etc/systemd/system/zypper-security-update.service
```

Paste the following service configuration:

```toml
[Unit]
Description=Automated End-of-Month Zypper Security Patches
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/zypper --non-interactive patch --category security --auto-agree-with-licenses
```

This configuration file creates a custom **systemd service unit** (`.service`) on SUSE Linux (SLES/openSUSE). Its job is to run a one-time execution command that silently installs all available security updates.

Here is a breakdown of what each section and directive does:

### **[Unit] Section**

Defines metadata and controls execution ordering relative to other system services.

* **`Description=`**: A human-readable summary of what the service does, visible in `systemctl status` and log output.

* **`After=network-online.target`**: Ensures systemd delays execution until the network stack is fully initialized and an active internet/network connection is present.
* **`Wants=network-online.target`**: Creates a soft dependency. It instructs systemd to pull in the network target during boot/activation without failing the service if the network target itself encounters an issue.

---

### **[Service] Section**

Defines how the service behaves when triggered.

* **`Type=oneshot`**: Tells systemd that this task executes a short, single action and then exits, rather than running continuously as a background daemon.

* **`ExecStart=`**: Specifies the exact binary path and CLI flags to execute:

* `/usr/bin/zypper`: The path to SUSE's standard package manager.

* `--non-interactive`: Suppresses user prompts and prevents the script from hanging while waiting for keyboard input.

* `patch --category security`: Restricts updates exclusively to security-related patches (ignoring standard feature upgrades).

* `--auto-agree-with-licenses`: Automatically accepts any software licenses associated with incoming security patches to avoid blocking execution.

### Step 2: Create the Systemd Timer Unit

```bash
sudo nano /etc/systemd/system/zypper-security-update.timer
```

Paste the following timer configuration:

```toml
[Unit]
Description=Timer for End-of-Month Zypper Security Patches

[Timer]
OnCalendar=*-*-~01 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

### Step 3: Running & Testing

To enable and start the timer:

```bash
sudo systemctl enable --now dnf-automatic-install.timer
```

Verify:

```bash
sudo systemctl list-timers dnf-automatic-install.timer
```

You should see something like this: 

```bash 
NEXT                        LEFT       LAST PASSED UNIT                            ACTIVATES
Tue 2026-09-01 02:00:00 CEST 4 days left n/a  n/a    dnf-automatic-install.timer     dnf-automatic-install.service
```

If you want to see the logs: 

```sh
sudo journalctl -u dnf-automatic-install.service
```

Typical output:

```sh
-- Logs begin at Mon 2026-08-01 00:00:00 CEST, end at Thu 2026-08-27 13:15:00 CEST. --
Aug 31 02:00:00 server01 systemd[1]: Starting dnf-automatic-install.service - dnf automatic install updates...
Aug 31 02:00:02 server01 dnf-automatic[14205]: Last metadata expiration check: 1:12:04 ago on Thu 27 Aug 2026 12:07:56 PM CEST.
Aug 31 02:00:05 server01 dnf-automatic[14205]: Dependencies resolved.
Aug 31 02:00:05 server01 dnf-automatic[14205]: ================================================================================
Aug 31 02:00:05 server01 dnf-automatic[14205]:  Package               Arch       Version                  Repository      Size
Aug 31 02:00:05 server01 dnf-automatic[14205]: ================================================================================
Aug 31 02:00:05 server01 dnf-automatic[14205]: Upgrading:
Aug 31 02:00:05 server01 dnf-automatic[14205]:  openssl-libs          x86_64     3.0.7-27.el9_4           rhel-9-appstream 2.2 M
Aug 31 02:00:05 server01 dnf-automatic[14205]:  kernel                x86_64     5.14.0-427.28.1.el9_4    rhel-9-baseos    5.2
...
...
```

> We usually check here the logs after the job has run.



## Automatic Updates On Debian / Ubuntu 

Both systems come pre-configured to **only install security updates by default**, leaving general feature updates for manual installation.

---

### Step-by-Step Setup (Works for both Debian & Ubuntu)

#### 1. Install and Enable the Package

Run the following commands to install the utility and enable the automated service:

```bash
sudo apt update
sudo apt install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -plow unattended-upgrades

```

When prompted in the terminal interface, select **YES** to enable automatic upgrades.

---

#### 2. Confirm the Daily Schedule

Enabling the service automatically creates the `/etc/apt/apt.conf.d/20auto-upgrades` file. You can verify its content with:

```bash
cat /etc/apt/apt.conf.d/20auto-upgrades

```

Ensure it contains these two lines (which tell APT to fetch package lists and run unattended upgrades once daily):

```ini
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";

```

---

#### 3. Verify "Security-Only" Rules (The Only Main Difference)

The configuration file `/etc/apt/apt.conf.d/50unattended-upgrades` defines which repositories are allowed to update automatically.

By default, both OSes restrict this to security channels, but the internal repository syntax differs slightly between them.

* **Ubuntu:** Uses `Allowed-Origins`. Open `/etc/apt/apt.conf.d/50unattended-upgrades` and ensure only the `-security` origin lines are active:
```text
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};

```

* **Debian:** Uses `Origins-Pattern`. Ensure only the `Debian-Security` line is uncommented:
```text
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};

```



---

### Useful Management Commands

* **Dry-Run (Test configuration without applying changes):**
```bash
sudo unattended-upgrade --dry-run --debug

```


* **Check Logs:**
```bash
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log

```


* **Check Pending Reboots:**
```bash
cat /var/run/reboot-required

```


To run Debian/Ubuntu `unattended-upgrades` specifically on the **third weekend of the month at 02:00 AM**, you adjust the underlying systemd timer (`apt-daily-upgrade.timer`) rather than the APT configuration itself.

Debian and Ubuntu use `apt-daily-upgrade.timer` to trigger the actual upgrade process.

---

### 4 Setup A Timer

Open the systemd drop-in editor for the upgrade timer:

```bash
sudo systemctl edit apt-daily-upgrade.timer

```

Paste the following configuration:

```ini
[Timer]
OnCalendar=
OnCalendar=Sat *-*-15..21 02:00:00
Persistent=true

```

> This example choose a date between day 15/21 of each month at 2:00 AM.
---

### 5 Disable the Download Timer (Optional but Recommended)

By default, APT runs a separate download task (`apt-daily.timer`) to fetch packages ahead of time. To force package downloading and installation to happen together at 02:00 AM during your maintenance window:

1. Edit the download timer:
```bash
sudo systemctl edit apt-daily.timer

```


2. Sync its schedule to match or run slightly earlier:
```ini
[Timer]
OnCalendar=
OnCalendar=Sat *-*-15..21 01:30:00
Persistent=true

```

---

### 6 Apply and Verify

Reload systemd and restart the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl restart apt-daily-upgrade.timer

```

Check when the systemd timer is scheduled to trigger next:

```bash
sudo systemctl list-timers apt-daily-upgrade.timer

```

**Expected Output:**
The **NEXT** column will show the date of the upcoming 3rd Saturday of the month at `02:00:00`.
