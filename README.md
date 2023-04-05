# ha-config
A shell utility script to easily manage your Home Assistant installation in Python venv
# How to use it:
Add exec permissions to the script in order to use it with:
```
chmod u+x ha-config.sh
```
Edit the file with:
```
nano ha-config.sh
```
Change the variables to match your installation:
```
# Configuration section
VENV_DIR="/srv/homeassistant"
CONFIG_DIR="/home/homeassistant/.homeassistant"
BACKUP_ROOT_DIR="/mnt/backup/Home Assistant"
LOG_DIR="/var/log/homeassistant"
```

Then run the script:
```
./ha-config.sh
```
