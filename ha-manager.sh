#!/bin/bash

# Configuration section
VENV_DIR="/srv/homeassistant"
CONFIG_DIR="/home/homeassistant/.homeassistant"
BACKUP_ROOT_DIR="/mnt/backup/Home Assistant"
LOG_DIR="/var/log/homeassistant"
HA_USER="homeassistant"

# Function to pause display
pause(){
 read -s -n 1 -p "Press any key to continue . . ."
 echo ""
}

# Function to get list of files in a directory
get_files() {
    let i=0 # define counting variable
    W=() # define working array
    while read -r line; do # process file by file
        i=$((i+1))
        W+=($i "$line")
    done < <( ls -1 "$1" )
    FILE_CHOICE=$(whiptail --title "List file of directory" --menu "Chose one" 24 80 17 "${W[@]}" 3>&2 2>&1 1>&3) # show dialog and store output
    if [ $? -eq 0 ]; then # Exit with OK
        FILE=$(ls -1 "$1" | sed -n "$(echo "$FILE_CHOICE p" | sed 's/ //')")
    fi
}

# Function to show backup/restore menu
show_backup_menu() {
    whiptail --title "Home Assistant Backup Manager" --menu "Select an option:" 15 60 7 \
    "1" "Backup the venv" \
    "2" "Backup the configuration" \
    "3" "Restore the venv" \
    "4" "Restore the configuration" 2>&1 > /dev/tty | tee -a "${LOG_DIR}/homeassistant-manager.log"
}

# function to handle restores
handle_backup() {

    # Prompt the directory 
    TITLE=$([ "$1" == 1 ] && echo "venv" || echo "configuration")
    DEST_DIR=$(whiptail --title "Backup ${TITLE}" --inputbox "Enter backup location:" 10 80 "${BACKUP_ROOT_DIR}/${TITLE}" 3>&1 1>&2 2>&3)

    # Check if user canceled or if no destination was entered
    if [ $? -ne 0 ] || [ -z "$DEST_DIR" ]; then
        echo "No destination. Operation canceled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
        return
    fi

    # Get current version of HA
    VERSION=$(sudo -u ${HA_USER} -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --version")

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
    whiptail --title "Backup" --msgbox "File created successfully!" 10 80

}

# function to handle restores
handle_restore() {

    TITLE=$([ "$1" == 3 ] && echo "venv" || echo "configuration")
  
    # Get list of available files
    get_files "${BACKUP_ROOT_DIR}/${TITLE}"

    # Check if user canceled or if no file was selected
    if [ $? -ne 0 ] || [ -z "$FILE" ]; then
        echo "No file selected. Operation canceled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
        return
    fi
   
    # Prompt the directory 
    TITLE=$([ "$1" == 3 ] && echo "venv" || echo "configuration")
    DEST_DIR=$(whiptail --title "Extract ${TITLE} Backup File" --inputbox "Enter extraction location:" 10 80 \""${BACKUP_ROOT_DIR}/${TITLE}"\" 3>&1 1>&2 2>&3)

    # Check if user canceled or if no destination was entered
    if [ $? -ne 0 ] || [ -z "$DEST_DIR" ]; then
        echo "No destination. Operation canceled." | tee -a "${LOG_DIR}/homeassistant-manager.log"
        return
    fi
    
    # Extract selected file to destination
    cmd="tar -xvfz \"${DIR}/${FILE}\" -C \"${DEST_DIR}\""
    eval "$cmd"
    
    # Display success message
    whiptail --title "Restore backup" --msgbox "File extracted successfully!" 10 80
}

# Function to display the main menu
show_main_menu() {
    STABLE=$(curl -s "https://pypi.org/pypi/homeassistant/json" | jq -r '.info.version')
    BETA=$(curl -s "https://api.github.com/repos/home-assistant/core/releases" | jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)
    whiptail --clear --title "Home Assistant Manager" --menu "Select an option:" 15 60 8 \
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
        echo "Upgrading to 'stable' channel..."
        VERSION=$(curl -s https://api.github.com/repos/home-assistant/core/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
        sudo -u ${HA_USER} -H -s /bin/bash -c "cd ${VENV_DIR} && source bin/activate && pip3 install -U homeassistant==${VERSION}" | 
        tee -a "${LOG_DIR}/homeassistant-manager.log"
    elif [ "$1" == "2" ]; then
        # Upgrade to Beta channel
        echo "Upgrading to 'beta' channel..."
        sudo -u ${HA_USER} -H -s /bin/bash -c "cd ${VENV_DIR} && source bin/activate && pip3 install --pre -u ${HA_USER}" | 
        tee -a "${LOG_DIR}/homeassistant-manager.log"
    fi
    pause
}

# Function to handle start, stop, and restart
handle_service() {
    if [ "$1" == "5" ]; then
        # Start Home Assistant
        echo "Starting Home Assistant..."
        sudo systemctl start home-assistant@${HA_USER}.service | tee -a "${LOG_DIR}/homeassistant-manager.log"
    elif [ "$1" == "6" ]; then
        # Stop Home Assistant
        echo "Stopping Home Assistant..."
        sudo systemctl stop home-assistant@${HA_USER}.service | tee -a "${LOG_DIR}/homeassistant-manager.log"
    elif [ "$1" == "7" ]; then
        # Restart Home Assistant
        echo "Restarting Home Assistant..."
        sudo systemctl restart home-assistant@${HA_USER}.service | tee -a "${LOG_DIR}/homeassistant-manager.log"
    fi
}

# Function to handle checking logs and configuration
handle_check() {
    if [ "$1" == "3" ]; then
        # Check Logs
        echo "Checking logs..."
        sudo journalctl -f -u home-assistant@${HA_USER}.service | less
    elif [ "$1" == "4" ]; then
        # Check Configuration
        echo "Checking configuration..."
        sudo -u ${HA_USER} -H -s /bin/bash -c "source ${VENV_DIR}/bin/activate && hass --script check_config" | 
        tee -a "${LOG_DIR}/homeassistant-manager.log"
        pause
    fi
}

# Create log directory (if needed)
sudo mkdir "${LOG_DIR}" > /dev/null 2>&1
sudo chmod 777 "${LOG_DIR}" > /dev/null 2>&1

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
            ;;
        *)
            exit
            ;;
    esac
done
