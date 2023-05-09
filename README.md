# ha-manager [![Codacy Badge](https://app.codacy.com/project/badge/Grade/304c18daae7f4429bbcc9d97b6f624cb)](https://app.codacy.com/gh/OToussaint/ha-manager/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
A shell utility script to easily manage your Home Assistant installation in Python venv.  
This script is using whiptail.
# How to use it:
Add exec permissions to the script in order to use it:
```
chmod u+x ha-manager.sh
```
Edit the config file:
```
nano ha-manager.json
```
Change the variables to match your installation:
```
{
    "VENV_DIR": "/srv/homeassistant",
    "CONFIG_DIR": "/home/homeassistant/.homeassistant",
    "BACKUP_ROOT_DIR": "/mnt/backup/Home Assistant",
    "LOG_DIR": "/var/log/homeassistant",
    "HA_USER": "homeassistant"
}
```

Then run the script:
```
./ha-manager.sh
```
![Main menu](https://github.com/OToussaint/ha-manager/raw/main/screenshots/ha-manager.png)
