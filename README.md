# ha-manager

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/d9b3fe18213f43af98177e9d67301616)](https://app.codacy.com/gh/OToussaint/ha-manager?utm_source=github.com&utm_medium=referral&utm_content=OToussaint/ha-manager&utm_campaign=Badge_Grade)

A shell utility script to easily manage your Home Assistant installation in Python venv.  
This script is using whiptail.
# How to use it:
Add exec permissions to the script in order to use it with:
```
chmod u+x ha-manager.sh
```
Edit the file with:
```
nano ha-manager.sh
```
Change the variables to match your installation:
```
# Configuration section
VENV_DIR="/srv/homeassistant"
CONFIG_DIR="/home/homeassistant/.homeassistant"
BACKUP_ROOT_DIR="/mnt/backup/Home Assistant"
LOG_DIR="/var/log/homeassistant"
HA_USER="homeassistant"
```

Then run the script:
```
./ha-manager.sh
```
