# My Linux Maintenance Scripts

Scripts for automating security patching and server reboot notifications on **Debian** and **Ubuntu** hosts with [ntfy](https://ntfy.sh) alerts (Chinese notification).

## Supported OS

- **Debian** and **Ubuntu** only (verified via `/etc/os-release` `ID`).
- Scripts are safe to re-run to update configuration parameters.

> **Uninstall note:** Uninstalling deletes the files managed by each script. Because the installers do not create backups, uninstalling cannot restore configuration that existed before installation.

---

## 1. Auto Security Patch (`install-auto-security-patch.sh`)

Sets up `unattended-upgrades`, `apt-listchanges`, and `needrestart`, enables periodic APT timers (`apt-daily.timer` and `apt-daily-upgrade.timer`), configures a `DPkg::Post-Invoke` hook to send daily deduplicated `ntfy` notifications, and runs `sudo unattended-upgrade --dry-run` upon completion.

### Usage

```bash
chmod +x install-auto-security-patch.sh
./install-auto-security-patch.sh --ntfy_url='https://...' [options]
```

### Options

| Flag                         | Required | Default              | Description                                                                                              |
| :--------------------------- | :------: | :------------------- | :------------------------------------------------------------------------------------------------------- |
| `--ntfy_url='URL'`           |   Yes    | —                    | Target `ntfy` endpoint URL (must start with `http://` or `https://`). Environment variables are ignored. |
| `--auto-reboot`              |    No    | Disabled (`"false"`) | Automatically reboot when required by security updates (e.g., kernel updates).                           |
| `--auto-reboot-time='HH:MM'` |    No    | `"03:30"`            | Scheduled reboot time in 24-hour `HH:MM` format.                                                         |
| `--tz='TIMEZONE'`            |    No    | Unchanged            | Set system timezone via `timedatectl` (e.g., `Asia/Hong_Kong`).                                          |
| `--uninstall`                |    No    | —                    | Remove managed configuration, notification files, and state. Must be used alone.                         |
| `-h`, `--help`               |    No    | —                    | Display usage information and exit.                                                                      |

`--ntfy_url` is required for installation only. `--uninstall` must be used without any other arguments.

### Examples

```bash
# Minimal setup (no auto-reboot, keep current timezone)
./install-auto-security-patch.sh --ntfy_url='https://ntfy.sh/my_server_noti'

# Full options with timezone and auto-reboot at 03:30
./install-auto-security-patch.sh \
  --ntfy_url='https://ntfy.sh/my_server_noti' \
  --auto-reboot \
  --auto-reboot-time='03:30' \
  --tz='Asia/Hong_Kong'
```

### Uninstall

```bash
./install-auto-security-patch.sh --uninstall
```

This disables and stops `apt-daily.timer` and `apt-daily-upgrade.timer`, removes `/usr/local/bin/notify-unattended-upgrades.sh` and both managed APT configuration files, and deletes `last-ntfy-date.stamp`, `last-ntfy-run.stamp`, and `last-ntfy-dpkg.stamp` from `/var/lib/unattended-upgrades/`. The `unattended-upgrades`, `apt-listchanges`, and `needrestart` packages remain installed, and the system timezone is left unchanged.

### Generated / Managed Files

- `/usr/local/bin/notify-unattended-upgrades.sh` — Parses today's unattended upgrade and `dpkg` logs, deduplicates per day via `/var/lib/unattended-upgrades/last-ntfy-date.stamp`, and posts a summary to `ntfy`.
- `/etc/apt/apt.conf.d/20auto-upgrades` — Sets periodic update, unattended upgrade, and `AutocleanInterval` (`"7"`).
- `/etc/apt/apt.conf.d/52unattended-upgrades-local` — Configures `Remove-Unused-Dependencies`, `Automatic-Reboot`, `Automatic-Reboot-Time`, `DPkg::Post-Invoke`, and allowed security origins.

> **Note:** Re-running the script overwrites `/usr/local/bin/notify-unattended-upgrades.sh` and resets any manual `NTFY_TOKEN` edit inside it back to `""`.

---

## 2. Reboot Notification (`install-reboot-notification.sh`)

Installs a `systemd` oneshot service (`notify-reboot.service`) that sends an `ntfy` notification containing boot time and kernel version once per `boot_id` after `network-online.target`. It also starts the service immediately after installation and prints recent `journalctl` logs.

### Usage

```bash
chmod +x install-reboot-notification.sh
./install-reboot-notification.sh --ntfy_url='https://...' [options]
```

### Options

| Flag               | Required | Default | Description                                                                                              |
| :----------------- | :------: | :------ | :------------------------------------------------------------------------------------------------------- |
| `--ntfy_url='URL'` |   Yes    | —       | Target `ntfy` endpoint URL (must start with `http://` or `https://`). Environment variables are ignored. |
| `--uninstall`      |    No    | —       | Remove the notification service, helper script, and state file. Must be used alone.                      |
| `-h`, `--help`     |    No    | —       | Display usage information and exit.                                                                      |

`--ntfy_url` is required for installation only. `--uninstall` must be used without any other arguments.

### Example

```bash
./install-reboot-notification.sh --ntfy_url='https://ntfy.sh/my_server_noti'
```

### Uninstall

```bash
./install-reboot-notification.sh --uninstall
```

This disables and stops `notify-reboot.service`, reloads systemd, and removes the service unit, `/usr/local/bin/notify-reboot.sh`, and `/var/lib/unattended-upgrades/last-ntfy-boot.stamp`. The `curl` package remains installed.

### Generated / Managed Files

- `/usr/local/bin/notify-reboot.sh` — Sends reboot details to `ntfy` and tracks `/var/lib/unattended-upgrades/last-ntfy-boot.stamp` per `boot_id` to avoid duplicate alerts on the same boot.
- `/etc/systemd/system/notify-reboot.service` — `systemd` unit triggered on boot after `network-online.target`.

> **Tip:** To trigger another test notification during re-runs on the same boot, remove `/var/lib/unattended-upgrades/last-ntfy-boot.stamp` before starting `notify-reboot.service`.
