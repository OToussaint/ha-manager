#!/bin/bash

# Create a daily backup function
create_daily_backup() {

    # Get current date
    local current_date
    current_date=$(date "+%Y-%m-%d")

    # Build the backup command
    cmd="cd \"$CONFIG_DIR\" && find . -name \"*\" -type f -print0 | grep -vz -E \"backups\/(.)+.tar$\" | grep -vz -E \"backups\/(.)+.tar.gz$\" | grep -vz -E \"\#recycle\" | sudo tar --ignore-failed-read -zvcf \"${BACKUP_DIR}/daily-${current_date}-${VERSION}.tar.gz\" --null -T -"

    eval "$cmd" || { echo "Failed to create a daily backup" >&2; exit 1; }
}

# Read config file
CONFIG_FILE="$(dirname "$0")/ha-manager.json"
if [ -f "$CONFIG_FILE" ]; then
  config=$(cat "$CONFIG_FILE")
else
  echo "Config file is missing: $CONFIG_FILE"
  exit 1
fi

# Decode JSON from the config file
VENV_DIR=$(echo "$config" | jq -r '.VENV_DIR // "/srv/homeassistant"')
CONFIG_DIR=$(echo "$config" | jq -r '.CONFIG_DIR // "/home/homeassistant/.homeassistant"')
HA_USER=$(echo "$config" | jq -r '.HA_USER // "homeassistant"')
BACKUP_DIR=$(echo "$config" | jq -r '.BACKUP_DIR // "/home/homeassistant/.homeassistant/backups"')
VERSION=$(sudo -u "${HA_USER}" -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --version")

# Validate VENV_DIR, CONFIG_DIR, and BACKUP_DIR directories
if [[ ! -d "${VENV_DIR}" || ! -d "${CONFIG_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
    echo "One or more directories specified in the configuration do not exist."
    exit 1
fi

# Check if HA_USER is a valid user
getent passwd "${HA_USER}" > /dev/null
if [ $? -ne 0 ]; then
    echo "The user '${HA_USER}' specified in the configuration is invalid."
    exit 1
fi

# Validate VERSION command
sudo -u "${HA_USER}" -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --version" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to get Home Assistant version. Please check the configuration and Home Assistant installation."
    exit 1
fi

# Manage weekly backup function
manage_weekly_backup() {
    local current_week
    current_week=$(date "+%Y-w%U")
    last_daily_backup=$(ls -1t "$BACKUP_DIR/daily-"* | head -n 1)

    # Create a weekly backup using the most recent daily backup if it exists
    latest_daily_backup=$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name "daily-*.tar.gz" -mtime -7 | sort | tail -1)

    if [ -n "${latest_daily_backup}" ]; then
        cp -p "${latest_daily_backup}" "${BACKUP_DIR}/weekly-${current_week}.tar.gz" 2>/dev/null || { echo "Failed to copy the latest daily backup for the weekly backup" >&2; exit 1; }
    fi
}

# Manage monthly backup function
manage_monthly_backup() {
    local last_daily_backup
    last_daily_backup=$(ls -1t "$BACKUP_DIR/daily-"* | head -n 1)
    last_month=$(date -d "last month" "+%Y-%m")

    # Create a monthly backup on the 1st day of the month
    if [ "$(date '+%d')" -eq "01" ]; then
        cp -p "$BACKUP_DIR/$last_daily_backup" "$BACKUP_DIR/monthly-${last_month}-${VERSION}.tar.gz" 2>/dev/null || { echo "Failed to copy the latest daily backup for the monthly backup" >&2; exit 1; }
    fi
}
# Everyday: create a daily backup
create_daily_backup || exit 1

# Every week, on Monday (day 1): create a weekly backup
if [ "$(date +%u)" -eq 1 ]; then
    manage_weekly_backup || exit 1
fi

# Every 1st of the month: create a monthly backup
if [ "$(date +%d)" = "01" ]; then
    manage_monthly_backup || exit 1
fi

# Remove old backups (keep 7 daily, 4 weekly, 12 monthly)
find "${BACKUP_DIR}" -type f -name "daily-*.tar.gz" -mtime +7 -delete || { echo "Failed to delete old daily backups" >&2; exit 1; }
find "${BACKUP_DIR}" -type f -name "weekly-*.tar.gz" -mtime +28 -delete || { echo "Failed to delete old weekly backups" >&2; exit 1; }
find "${BACKUP_DIR}" -type f -name "monthly-*.tar.gz" -mtime +365 -delete || { echo "Failed to delete old monthly backups" >&2; exit 1; }