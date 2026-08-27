# Automatic Updates Implementation Guide
**Authored by:** Cesar Valdez

---

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
* **`~01` (Day):** The tilde (`~`) syntax represents counting days **backwards from the end of the month**. `~01` targets the **last day of the month**.

* Systemd automatically handles different month lengths, correctly targeting the 28th/29th of February, the 30th of April/June/September/November, and the 31st of all other months.

> On RHEL 9.8 the `~` is not supported. 

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