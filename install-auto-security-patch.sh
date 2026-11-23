#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Unattended Upgrades & ntfy Notification Installer
#
# Usage:
#   ./install-auto-security-patch.sh --ntfy_url='https://...' [options]
#   ./install-auto-security-patch.sh --uninstall
#
# Required Arguments (installation only):
#   --ntfy_url='URL'          Target ntfy endpoint URL (must start with http://
#                             or https://). Environment variables are ignored.
#
# Optional Arguments:
#   --auto-reboot             Enable automatic reboot when required by updates.
#                             (Default: disabled / "false")
#   --auto-reboot-time='HH:MM'
#                             Scheduled reboot time in 24-hour HH:MM format.
#                             (Default: "03:30")
#   --tz='TIMEZONE'           Set system timezone via timedatectl, e.g.,
#                             "Asia/Hong_Kong". (Default: unchanged)
#   --uninstall               Remove managed configuration, notification script,
#                             and state files. Must be used alone. Packages and
#                             system timezone are left unchanged.
#   -h, --help                Display this usage message and exit.
#
# Supported OS:
#   Debian or Ubuntu only (checked via /etc/os-release ID).
#
# Examples:
#   ./install-auto-security-patch.sh --ntfy_url='https://ntfy.sh/my_server_noti'
#   ./install-auto-security-patch.sh --ntfy_url='https://ntfy.sh/my_server_noti' \
#     --auto-reboot --auto-reboot-time='03:30' --tz='Asia/Hong_Kong'
#   ./install-auto-security-patch.sh --uninstall
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
NTFY_CONFIG="/etc/ntfy-unattended-upgrades.conf"
AUTO_REBOOT="false"
AUTO_REBOOT_TIME="03:30"
TZ_NAME=""
UNINSTALL="false"

usage() {
  local status="${1:-1}"
  local fd=2
  if [ "$status" -eq 0 ]; then
    fd=1
  fi
  cat <<'EOF' >&"$fd"
Usage: ./install-auto-security-patch.sh --ntfy_url='https://...' [--auto-reboot] [--auto-reboot-time='03:30'] [--tz='Asia/Hong_Kong']
       ./install-auto-security-patch.sh --uninstall
EOF
  exit "$status"
}

uninstall() {
  echo "Removing automatic security patching and ntfy notifications..."
  sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer
  sudo rm -f \
    /etc/apt/apt.conf.d/20auto-upgrades \
    /etc/apt/apt.conf.d/52unattended-upgrades-local \
    /etc/ntfy-unattended-upgrades.conf \
    /usr/local/bin/notify-unattended-upgrades.sh \
    /var/lib/unattended-upgrades/last-ntfy-date.stamp \
    /var/lib/unattended-upgrades/last-ntfy-run.stamp \
    /var/lib/unattended-upgrades/last-ntfy-dpkg.stamp

  echo "========================================================================"
  echo "Uninstallation complete. APT packages and system timezone were left unchanged."
  echo "========================================================================"
}

write_ntfy_config() {
  local token_line='NTFY_TOKEN=""'
  local existing_token_line=""

  # Preserve a manually configured token while replacing the URL on re-runs.
  if sudo test -f "$NTFY_CONFIG"; then
    existing_token_line="$(sudo grep -m 1 '^NTFY_TOKEN=' "$NTFY_CONFIG" || true)"
    if [ -n "$existing_token_line" ]; then
      token_line="$existing_token_line"
    fi
  fi

  {
    printf 'NTFY_URL=%q\n' "$NTFY_URL"
    printf '%s\n' "$token_line"
  } | sudo tee "$NTFY_CONFIG" >/dev/null
  sudo chmod 0600 "$NTFY_CONFIG"
  sudo bash -n "$NTFY_CONFIG"
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
    --auto-reboot)
      AUTO_REBOOT="true"
      ;;
    --auto-reboot-time=*)
      AUTO_REBOOT_TIME="${1#*=}"
      ;;
    --auto-reboot-time)
      [ "$#" -ge 2 ] || usage
      AUTO_REBOOT_TIME="$2"
      shift
      ;;
    --tz=*)
      TZ_NAME="${1#*=}"
      ;;
    --tz)
      [ "$#" -ge 2 ] || usage
      TZ_NAME="$2"
      shift
      ;;
    --uninstall)
      UNINSTALL="true"
      ;;
    -h|--help)
      usage 0
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

# Validate reboot time format (HH:MM)
if ! [[ "$AUTO_REBOOT_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo "Error: --auto-reboot-time must be in HH:MM (24-hour) format, e.g., 03:30" >&2
  exit 1
fi

# Set timezone if --tz is provided
if [ -n "$TZ_NAME" ]; then
  sudo timedatectl set-timezone "$TZ_NAME"
fi

sudo apt update && sudo apt install -y unattended-upgrades apt-listchanges needrestart curl

cat <<'EOF' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

write_ntfy_config

sudo tee /usr/local/bin/notify-unattended-upgrades.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/ntfy-unattended-upgrades.conf"
if [ ! -r "$CONFIG_FILE" ]; then
  echo "Error: ntfy configuration '$CONFIG_FILE' is missing or unreadable." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$CONFIG_FILE"
: "${NTFY_URL:?Set NTFY_URL in $CONFIG_FILE}"
NTFY_TOKEN="${NTFY_TOKEN:-}"

case "$NTFY_URL" in
  http://*|https://*) ;;
  *)
    echo "Error: NTFY_URL in '$CONFIG_FILE' must start with http:// or https://." >&2
    exit 1
    ;;
esac

MAX_PKGS=15

MAIN_LOG="/var/log/unattended-upgrades/unattended-upgrades.log"
DPKG_LOG="/var/log/unattended-upgrades/unattended-upgrades-dpkg.log"
STATE_FILE="/var/lib/unattended-upgrades/last-ntfy-date.stamp"
HOST="$(hostname -s 2>/dev/null || hostname)"
TODAY="$(date '+%Y-%m-%d')"

[ -f "$MAIN_LOG" ] && [ -f "$DPKG_LOG" ] || exit 0

# Skip if a notification has already been sent today
PREV_DATE="$(cat "$STATE_FILE" 2>/dev/null || true)"
[ "$TODAY" = "$PREV_DATE" ] && exit 0

# Verify unattended-upgrades ran today and had packages to upgrade
awk -v d="$TODAY" '
  $1 == d && /Packages that will be upgraded:/ { found = 1 }
  END { exit (found ? 0 : 1) }
' "$MAIN_LOG" || exit 0

# Extract and deduplicate unpacked packages from all of today's "Log started: YYYY-MM-DD ..." blocks
ALL_PKGS="$(awk -v d="$TODAY" '
  /^Log started:/ {
    # Log started: YYYY-MM-DD  HH:MM:SS
    active = ($3 == d) ? 1 : 0
  }
  active && /^Unpacking / {
    pkg = $2; sub(/:.*/, "", pkg)
    ver = $3; gsub(/[()]/, "", ver)
    if (pkg != "" && ver != "" && !seen[pkg "@" ver]++) {
      print pkg "@" ver
    }
  }
' "$DPKG_LOG")"

[ -n "$ALL_PKGS" ] || exit 0

PKG_COUNT="$(printf '%s\n' "$ALL_PKGS" | wc -l)"
SHOWN_PKGS="$(printf '%s\n' "$ALL_PKGS" | head -n "$MAX_PKGS")"
if [ "$PKG_COUNT" -gt "$MAX_PKGS" ]; then
  EXTRA="$((PKG_COUNT - MAX_PKGS))"
  SHOWN_PKGS="${SHOWN_PKGS}
... +${EXTRA} more"
fi

BODY="已更新 ${PKG_COUNT} 個套件
${SHOWN_PKGS}"

CURL_ARGS=(
  -fsS
  --globoff
  --connect-timeout 5
  --max-time 15
  -X POST
  -H "Title: 🆙 ${HOST} 已安裝安全性更新"
  -H "Priority: default"
  -H "Tags: linux,autoupgrade"
  --data-binary "$BODY"
)

if [ -n "$NTFY_TOKEN" ]; then
  CURL_ARGS+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
fi

send_notification() {
  local attempt
  for attempt in 1 2 3; do
    if curl "${CURL_ARGS[@]}" "$NTFY_URL" >/dev/null; then
      return 0
    fi
    if [ "$attempt" -lt 3 ]; then
      sleep 5
    fi
  done
  return 1
}

send_notification

mkdir -p "$(dirname "$STATE_FILE")"
printf '%s\n' "$TODAY" > "$STATE_FILE"
EOF

sudo chmod 0755 /usr/local/bin/notify-unattended-upgrades.sh
sudo rm -f /var/lib/unattended-upgrades/last-ntfy-run.stamp /var/lib/unattended-upgrades/last-ntfy-dpkg.stamp

cat <<EOF | sudo tee /etc/apt/apt.conf.d/52unattended-upgrades-local >/dev/null
// Automatically remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Reboot only when required (e.g., kernel updates)
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-Time "${AUTO_REBOOT_TIME}";

// Trigger single notification script after dpkg finishes (deduplicated per day)
DPkg::Post-Invoke { "/usr/local/bin/notify-unattended-upgrades.sh || true"; };

// Allow security update origins
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
EOF

# Run dry-run after installation to verify configuration
sudo unattended-upgrade -d --dry-run

# Enable system timer
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer

##### INSTALL COMPLETE #####
echo "========================================================================"
echo "Installation complete. Please check the output and logs above for any errors."
echo "Logs: /var/log/unattended-upgrades/unattended-upgrades.log"
echo "If you want to patch system now, run 'sudo unattended-upgrade -d'"
echo "========================================================================"
