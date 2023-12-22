#!/bin/bash

# Create a daily backup function
create_daily_backup() {

    # Get current date
    local current_date
    current_date=$(date "+%Y-%m-%d")

    # Build the backup command
    cmd="cd \"$CONFIG_DIR\" && find . -name \"*\" -type f -print0 | grep -vz -E \"backups\/(.)+.tar$\" | grep -vz -E \"backups\/(.)+.tar.gz$\" | grep -vz -E \"\#recycle\" | sudo tar --ignore-failed-read -zvcf \"${BACKUP_DIR}/daily-${current_date}-${VERSION}.tar.gz\" --null -T -"

    eval "$cmd"  # Execute the backup command
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
BACKUP_DIR=$(echo "$config" | jq -r '.BACKUP_DIR // "homeassistant"')
VERSION=$(sudo -u "${HA_USER}" -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --version")

# Manage weekly backup function
manage_weekly_backup() {
    local current_week
    current_week=$(date "+%Y-w%U")
    last_daily_backup=$(ls -1t "$BACKUP_DIR/daily-"* | head -n 1)

    # Create a weekly backup if there's a recent daily backup
    if [ -n "$last_daily_backup" ]; then
        cp -p "$BACKUP_DIR/$last_daily_backup" "$BACKUP_DIR/weekly-${current_week}.tar.gz" 2>/dev/null
    fi

    latest_daily_backup=$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name "daily-*.tar.gz" -mtime -7 | sort | tail -1)

    # Create a weekly backup with the latest daily backup content
    if [ -n "${latest_daily_backup}" ]; then
        cp -p "${latest_daily_backup}" "${BACKUP_DIR}/weekly-${current_week}-${VERSION}.tar.gz" 2>/dev/null
    fi
}

# Manage monthly backup function
manage_monthly_backup() {
    local last_daily_backup
    last_daily_backup=$(ls -1t "$BACKUP_DIR/daily-"* | head -n 1)
    last_month=$(date -d "last month" "+%Y-%m")

    # Create a monthly backup on the 1st day of the month
    if [ "$(date '+%d')" -eq "01" ]; then
        cp -p "$BACKUP_DIR/$last_daily_backup" "$BACKUP_DIR/monthly-${last_month}-${VERSION}.tar.gz" 2>/dev/null
    fi
}

# Everyday: create a daily backup
create_daily_backup

# Every week, on Monday (day 1): create a weekly backup
if [ "$(date +%u)" -eq 1 ]; then
    manage_weekly_backup
fi

# Every 1st of the month: create a monthly backup
if [ "$(date +%d)" = "01" ]; then
    manage_monthly_backup
fi

# Remove old backups (keep 7 daily, 4 weekly, 12 monthly)
find "${BACKUP_DIR}" -type f -name "daily-*.tar.gz" -mtime +7 -delete
find "${BACKUP_DIR}" -type f -name "weekly-*.tar.gz" -mtime +28 -delete
find "${BACKUP_DIR}" -type f -name "monthly-*.tar.gz" -mtime +365 -delete