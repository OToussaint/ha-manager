#!/bin/bash

# Check if jq is installed (to read config file)
if ! which tee >/dev/null; then
  echo "Error: jq is required to read the configuration file but not installed. Aborting."
  exit 1
fi

# Read config file
# Load the config file
CONFIG_FILE="$(dirname "$0")/ha-manager.json"
if [ -f "$CONFIG_FILE" ]; then
  config=$(cat "$CONFIG_FILE")
else
  echo "Config file not found: $CONFIG_FILE"
  exit 1
fi

# Get the values from the config file with default values
VENV_DIR=$(echo "$config" | jq -r '.VENV_DIR // "/srv/homeassistant"')
CONFIG_DIR=$(echo "$config" | jq -r '.CONFIG_DIR // "/home/homeassistant/.homeassistant"')
BACKUP_ROOT_DIR=$(echo "$config" | jq -r '.BACKUP_ROOT_DIR // "/mnt/backup/Home Assistant"')
LOG_DIR=$(echo "$config" | jq -r '.LOG_DIR // "/var/log/homeassistant"')
HA_USER=$(echo "$config" | jq -r '.HA_USER // "homeassistant"')

# Test environment
directories=("${VENV_DIR}" "${CONFIG_DIR}")
for dir in "${directories[@]}"; do
    if ! test -d "${dir}"; then
        echo "Error: Directory ${dir} does not exist. Aborting"
        exit 1
    fi
done

# Test write access to the directory
if ! test -w "${LOG_DIR}"; then
    echo "Error: You do not have write access to ${LOG_DIR}. Aborting"
    exit 1
fi

# Check if required tools are installed
if ! which tee >/dev/null; then
  echo "Error: tee is required but not installed. Aborting."
  exit 1
fi

required_commands=(sudo whiptail curl jq sed dos2unix tput)

for cmd in "${required_commands[@]}"; do
  if ! command -v "${cmd}" >/dev/null; then
    echo "Error: ${cmd} is required but not installed. Aborting." | tee -a "${LOG_DIR}/homeassistant-manager.log"
    exit 1
  fi
done

# Full test of backup/restore capabilities
if which tar >/dev/null; then
    # Check if sudo to root user is possible
    if sudo -s tar --help >/dev/null 2>&1; then
        # Test write access to the directory
        if test -w "${BACKUP_ROOT_DIR}"; then
            BR=1
        else
            echo "Warning: You do not have write access to ${BACKUP_ROOT_DIR}. Backup/Restore will be disabled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
            BR=0
        fi
    else
      echo "Warning: sudo to root failed. Backup/Restore will be disabled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
      BR=0
    fi
else
  echo "Warning: tar is required but not installed. Backup/Restore will be disabled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
  BR=0
fi

# Check if sudo to HA user is possible
if sudo -u "${HA_USER}" -H -s ls >/dev/null 2>&1; then
  echo -n ""
else
  echo "Error: sudo to ${HA_USER} failed but it is required. Aborting." | tee -a "${LOG_DIR}/homeassistant-manager.log"
  exit 1
fi

# Function to retry curl if it fails
my_curl() {
    local retries=$1
    shift
    local response=

    for i in $(seq "$retries"); do
        response=$(curl -s "$@")

        if [ -n "$response" ]; then
            echo "$response"
            return 0
        fi

        sleep 1
    done

    return 1
}

# Function to pause display
pause(){
 read -r -s -n 1 -p "Press any key to continue . . ."
 echo ""
}

# Function to get list of files in a directory
get_files() {
    (( i=0 )) # define counting variable
    W=() # define working array
    while read -r line; do # process file by file
        i=$((i+1))
        W+=("$i" "$line")
    done < <( ls -1r "$1" )
    if FILE_CHOICE=$(whiptail --title "List file of directory" --menu "Chose one" $((rows < 24 ? rows : 24)) $((columns < 80 ? columns : 80)) $((rows < 24 ? rows - 7 : 17)) "${W[@]}" 3>&2 2>&1 1>&3); then
        FILE=$(find "$1" -type f -printf '%T@ %f\n' | sort -rn | sed -n "$FILE_CHOICE p" | sed 's/^[0-9.]\+ //;s/\(.*\)/\1/')
    fi
}

# Function to show backup/restore menu
show_backup_menu() {
    whiptail --title "Home Assistant Backup Manager" --menu "Select an option:" $((rows < 15 ? rows : 15)) $((columns < 60 ? columns : 60)) 4 \
    "1" "Backup the venv" \
    "2" "Backup the configuration" \
    "3" "Restore the venv" \
    "4" "Restore the configuration" 2>&1 > /dev/tty | tee -a "${LOG_DIR}/homeassistant-manager.log"
}

# Function to backup a SQLite DB (e.g.: home-assistant_v2.db)
backup_SQLite() {
    local DB_FILE="$1"
    local DEST_DIR="$2"
    if ! test -f "$DB_FILE"; then
        echo "Error: file ${1} doesn't exist." | tee -a "${LOG_DIR}/homeassistant-manager.log"
        pause
        return
    fi

    # Get current version of HA
    VERSION=$(sudo -u "${HA_USER}" -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --version")
    cmd+="sqlite3 \"${DB_FILE}\" \".backup '${DEST_DIR}/${VERSION}-db-$(date +%F).db.backup'\""
    eval "$cmd"

    # Display success message
    whiptail --title "Backup" --msgbox "File created successfully!" $((rows < 10 ? rows : 10)) $((columns < 60 ? columns : 60))
}

# Function to backup a MySQL/MariaDB database
backup_mySQL() {
    # I'll need some additional info for that
    # Shut down the MariaDB/MySQL service
    # Dump the DB like 'mysqldump --user=admin_backup --password --lock-tables --databases db1 >/backupdir/dbnameback.sql'
    # Restart MariaDB/MySQL
    echo ""
}

# Function to backup a PostgreSQL database
backup_postgreSQL() {
    # I'll need some additional info for that
    # Shut down the PostgreSQL service.
    # Dump the DB like 'PostgreSQLdump -u root -p dbname >/backupdir/dbnameback.sql'
    # Restart PostgreSQL.
    echo ""
}

# function to handle restores
handle_backup() {

    # Prompt the directory 
    TITLE=$([ "$1" == 1 ] && echo "venv" || echo "configuration")

    # Check if user canceled or if no destination was entered
    if ! DEST_DIR=$(whiptail --title "Backup ${TITLE}" --inputbox "Enter backup location:" $((rows < 10 ? rows : 10)) $((columns < 80 ? columns : 80)) "${BACKUP_ROOT_DIR}/${TITLE}" 3>&1 1>&2 2>&3) || [ -z "$DEST_DIR" ]; then
        echo "Info: No destination. Operation canceled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
        return
    fi

    # Get current version of HA
    VERSION=$(sudo -u "${HA_USER}" -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --version")

    # Extract selected file to destination
    if [ "$1" == "1" ]; then
        DIR="${VENV_DIR}"
        NAME="venv"

    elif [ "$1" == "2" ]; then
        DIR="${CONFIG_DIR}"
        NAME="configuration"
    fi

    # Build command
    cmd="cd \"$DIR\" && find . -name \"*\" -type f -print0 | "

    if [ "$1" == "2" ]; then
        cmd+=" grep -vz -E \"backups\/(.)+.tar$\" | " 
    fi
    cmd+=" sudo tar --ignore-failed-read -zvcf \"${DEST_DIR}/${VERSION}-${NAME}-$(date +%F).tar.gz\" --null -T -"
    eval "$cmd"

    # Display success message
    whiptail --title "Backup" --msgbox "File created successfully!" $((rows < 10 ? rows : 10)) $((columns < 80 ? columns : 80))

}

# function to handle restores
handle_restore() {

    TITLE=$([ "$1" == 3 ] && echo "venv" || echo "configuration")
  
    # Get list of available files
    if ! get_files "${BACKUP_ROOT_DIR}/${TITLE}" || [ -z "$FILE" ]; then
        echo "No file selected. Operation canceled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
        return
    fi
   
    # Prompt the directory 
    TITLE=$([ "$1" == 3 ] && echo "venv" || echo "configuration")
    if ! DEST_DIR=$(whiptail --title "Extract ${TITLE} Backup File" --inputbox "Enter extraction location:" $((rows < 10 ? rows : 10)) $((columns < 80 ? columns : 80)) "${BACKUP_ROOT_DIR}/${TITLE}" 3>&1 1>&2 2>&3) || [ -z "$DEST_DIR" ]; then
        echo "Info: No destination. Operation canceled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
        return
    fi
    
    # Extract selected file to destination
    cmd="tar -xvfz \"${DIR}/${FILE}\" -C \"${DEST_DIR}\""
    eval "$cmd"
    
    # Display success message
    whiptail --title "Restore backup" --msgbox "File extracted successfully!" $((rows < 10 ? rows : 10)) $((columns < 80 ? columns : 80))
}

# Function to display the main menu
show_main_menu() {
    STABLE=$(curl -s "https://pypi.org/pypi/homeassistant/json" | jq -r '.info.version')
    BETA=$(curl -s "https://api.github.com/repos/home-assistant/core/releases" | jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)
    whiptail --clear --title "Home Assistant Manager" --menu "Select an option:" $((rows < 15 ? rows : 15)) $((columns < 60 ? columns : 60)) 8 \
    "1" "Upgrade to 'stable' channel (${STABLE})" \
    "2" "Upgrade to 'beta' channel (${BETA})" \
    "3" "Check logs" \
    "4" "Check configuration" \
    "5" "Start Home Assistant" \
    "6" "Stop Home Assistant" \
    "7" "Restart Home Assistant" \
    "8" "Backup/Restore configuration" 2>&1 > /dev/tty | tee -a "${LOG_DIR}/homeassistant-manager.log"
}

# Function to handle upgrades
handle_upgrade() {
    if [ "$1" == "1" ]; then
        # Upgrade to Release channel
        echo "Info: Upgrading to 'stable' channel..."
        VERSION=$(my_curl 5 https://api.github.com/repos/home-assistant/core/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
        sudo -u "${HA_USER}" -H -s /bin/bash -c "cd ${VENV_DIR} && source bin/activate && pip3 install -U homeassistant==${VERSION}" | 
        tee -a "${LOG_DIR}/homeassistant-manager.log"
        # Show release note
        tempfile=$(mktemp)
        my_curl 5 https://api.github.com/repos/home-assistant/core/releases/latest | jq -r '.body' | grep -E "^-" | while read -r line; do  echo "$line" | dos2unix | sed 's/([^)]*)//g' | fold -w 70 -s | sed '2,$ s/^/    /' >> "${tempfile}"; done
        whiptail --scrolltext --title "Latest 'stable' Release Notes" --textbox "${tempfile}" $((rows < 30 ? rows : 30)) $((columns < 100 ? columns : 100))
        rm -f "${tempfile}"
    elif [ "$1" == "2" ]; then
        # Upgrade to Beta channel
        echo "Info: Upgrading to 'beta' channel..."
        sudo -u "${HA_USER}" -H -s /bin/bash -c "cd ${VENV_DIR} && source bin/activate && pip3 install --pre -u ${HA_USER}" | 
        tee -a "${LOG_DIR}/homeassistant-manager.log"
        tempfile=$(mktemp)
        my_curl 5 https://api.github.com/repos/home-assistant/core/releases | jq -r '.[] | select(.prerelease == true) | .body' | sed '/^$/q' | grep -E "^-" | while read -r line; do  echo "$line" | dos2unix | sed 's/([^)]*)//g' | fold -w 70 -s | sed '2,$ s/^/    /' >> "${tempfile}"; done
        whiptail --scrolltext --title "Latest 'beta' Release Notes" --textbox "${tempfile}" $((rows < 30 ? rows : 30)) $((columns < 100 ? columns : 100))
        rm -f "${tempfile}"
    fi
}

# Function to handle start, stop, and restart
handle_service() {
    if [ "$1" == "5" ]; then
        # Start Home Assistant
        echo "Info: Starting Home Assistant..."
        sudo systemctl start home-assistant@"${HA_USER}".service | tee -a "${LOG_DIR}/homeassistant-manager.log"
    elif [ "$1" == "6" ]; then
        # Stop Home Assistant
        echo "Info: Stopping Home Assistant..."
        sudo systemctl stop home-assistant@"${HA_USER}".service | tee -a "${LOG_DIR}/homeassistant-manager.log"
    elif [ "$1" == "7" ]; then
        # Restart Home Assistant
        echo "Info: Restarting Home Assistant..."
        sudo systemctl restart home-assistant@"${HA_USER}".service | tee -a "${LOG_DIR}/homeassistant-manager.log"
    fi
}

# Function to handle checking logs and configuration
handle_check() {
    if [ "$1" == "3" ]; then
        # Check Logs
        echo "Info: Checking logs...press ^C when done"
        sudo journalctl -f -u home-assistant@"${HA_USER}".service
    elif [ "$1" == "4" ]; then
        # Check Configuration
        echo "Info: Checking configuration..."
        sudo -u "${HA_USER}" -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --script check_config" | 
        tee -a "${LOG_DIR}/homeassistant-manager.log"
        pause
    fi
}

rows=$(tput lines)
columns=$(tput cols)

function cleanup() {
    echo ""
}

# Intercept the ctrl+c signal and call the cleanup function
trap cleanup SIGINT

# Main loop
while true; do
    choice=$(show_main_menu)

    case $choice in
        1|2)
            handle_upgrade "$choice"
            ;;
        3|4)
            handle_check "$choice"
            ;;
        5|6|7)
            handle_service "$choice"
            ;;
        8)
            if [ $BR -eq 0 ]
            then
                # Display error message
                whiptail --title "Backup/Restore" --msgbox "Backup/Restore is unavailable, check the log file for more information" $((rows < 10 ? rows : 10)) $((columns < 80 ? columns : 80))
            else
                sub_choice=$(show_backup_menu)
    
                case $sub_choice in
                    1|2)
                        handle_backup "$sub_choice"
                        ;;
                    3|4)
                        handle_restore "$sub_choice"
                        ;;
                    *)
                        break
                        ;;
                esac
            fi
            ;;
        *)
            exit
            ;;
    esac
done
