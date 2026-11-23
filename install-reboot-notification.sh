#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Reboot Notification Installer (ntfy + systemd)
#
# Usage:
#   ./install-reboot-notification.sh --ntfy_url='https://...' [options]
#   ./install-reboot-notification.sh --uninstall
#
# Required Arguments (installation only):
#   --ntfy_url='URL'          Target ntfy endpoint URL (must start with http://
#                             or https://). Environment variables are ignored.
#
# Optional Arguments:
#   --uninstall               Remove the notification service, helper script,
#                             and state file. Must be used alone. curl is left
#                             installed.
#   -h, --help                Display this usage message and exit.
#
# Supported OS:
#   Debian or Ubuntu only (checked via /etc/os-release ID).
#
# Examples:
#   ./install-reboot-notification.sh --ntfy_url='https://ntfy.sh/my_server_noti'
#   ./install-reboot-notification.sh --uninstall
################################################################################

# Check if the host OS is Debian or Ubuntu before proceeding
if [ ! -r /etc/os-release ]; then
  echo "Error: /etc/os-release not found; cannot verify OS." >&2
  exit 1
fi

OS_ID="$(
  . /etc/os-release
  printf '%s' "${ID:-}"
)"

case "$OS_ID" in
  debian|ubuntu) ;;
  *)
    echo "Error: Unsupported OS '${OS_ID:-unknown}'. Only Debian and Ubuntu are supported." >&2
    exit 1
    ;;
esac

ARG_COUNT="$#"
NTFY_URL=""
UNINSTALL="false"

usage() {
  cat <<'EOF' >&2
Usage: ./install-reboot-notification.sh --ntfy_url='https://...'
       ./install-reboot-notification.sh --uninstall
EOF
  exit 1
}

uninstall() {
  echo "Removing reboot notification service..."
  if [ -f /etc/systemd/system/notify-reboot.service ]; then
    sudo systemctl disable --now notify-reboot.service
  fi

  sudo rm -f \
    /etc/systemd/system/notify-reboot.service \
    /usr/local/bin/notify-reboot.sh \
    /var/lib/unattended-upgrades/last-ntfy-boot.stamp

  sudo systemctl daemon-reload
  # The unit may already be absent when uninstall is repeated.
  sudo systemctl reset-failed notify-reboot.service 2>/dev/null || true

  echo "========================================================================"
  echo "Uninstallation complete. curl was left installed."
  echo "========================================================================"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ntfy_url=*)
      NTFY_URL="${1#*=}"
      ;;
    --ntfy_url)
      [ "$#" -ge 2 ] || usage
      NTFY_URL="$2"
      shift
      ;;
    --uninstall)
      UNINSTALL="true"
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
  shift
done

if [ "$UNINSTALL" = "true" ]; then
  if [ "$ARG_COUNT" -ne 1 ]; then
    echo "Error: --uninstall must be used without other arguments." >&2
    usage
  fi
  uninstall
  exit 0
fi

# Validate required --ntfy_url for installation and ensure http:// or https:// prefix
[ -n "$NTFY_URL" ] || {
  echo "Error: --ntfy_url is required." >&2
  usage
}

case "$NTFY_URL" in
  http://*|https://*) ;;
  *)
    echo "Error: --ntfy_url must start with http:// or https://" >&2
    exit 1
    ;;
esac

# Ensure curl is available for sending ntfy notifications
if ! command -v curl >/dev/null 2>&1; then
  sudo apt update && sudo apt install -y curl
fi

##### REBOOT NOTIF #####
sudo tee /usr/local/bin/notify-reboot.sh >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Baked-in ntfy URL from --ntfy_url argument
NTFY_URL="${NTFY_URL}"
NTFY_TOKEN="" # Set token if authentication is required, e.g., "tk_xxxxxxxx"
STATE_FILE="/var/lib/unattended-upgrades/last-ntfy-boot.stamp"
HOST="\$(hostname -s 2>/dev/null || hostname)"
BOOT_ID="\$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"

# Send notification only once per boot_id
if [ -n "\$BOOT_ID" ] && [ "\$BOOT_ID" = "\$(cat "\$STATE_FILE" 2>/dev/null || true)" ]; then
  exit 0
fi

KERNEL_REL="\$(uname -r 2>/dev/null || echo unknown)"
BOOT_TIME="\$(uptime -s 2>/dev/null || echo unknown)"
BODY="開機時間: \${BOOT_TIME}
Kernel: \${KERNEL_REL}"

CURL_ARGS=(
  -fsS
  -X POST
  -H "Title: 🔄 \${HOST} 已重新開機"
  -H "Priority: default"
  -H "Tags: linux,boot"
  --data-binary "\$BODY"
)

if [ -n "\$NTFY_TOKEN" ]; then
  CURL_ARGS+=(-H "Authorization: Bearer \${NTFY_TOKEN}")
fi

curl "\${CURL_ARGS[@]}" "\$NTFY_URL" >/dev/null

if [ -n "\$BOOT_ID" ]; then
  mkdir -p "\$(dirname "\$STATE_FILE")"
  printf '%s\n' "\$BOOT_ID" > "\$STATE_FILE"
fi
EOF

sudo chmod +x /usr/local/bin/notify-reboot.sh

sudo tee /etc/systemd/system/notify-reboot.service >/dev/null <<'EOF'
[Unit]
Description=Notify ntfy on server reboot
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/notify-reboot.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable notify-reboot.service

sudo rm -f /var/lib/unattended-upgrades/last-ntfy-boot.stamp

sudo systemctl start notify-reboot.service
sudo journalctl -u notify-reboot.service -n 10 --no-pager

##### INSTALL COMPLETE #####
echo "========================================================================"
echo "Installation complete. Please check the output and logs above for any errors."
echo "Service logs: sudo journalctl -u notify-reboot.service -n 20 --no-pager"
echo "========================================================================"
