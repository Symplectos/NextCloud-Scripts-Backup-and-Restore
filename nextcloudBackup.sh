#!/bin/bash

########################################################################################################################
# Bash script to create backups of a NextCloud instance
#
# Author: Gilles Bellot
# Date: 27/03/2021
# Location: Lenningen, Luxembourg
#
# Notes:
#  - if a backup tool like Borg is used, compression should be set to false
#  - the following three secrets must exist in the "nextcloud" encpass bucket of the root user:
#    - db: the name of the NextCloud database
#    - dbUser: the user to access the above database
#    - dbPassword: the password to authenticate the above user with
#
# References:
#  - DetaTec: https://github.com/DecaTec/
#  - EncPass: https://github.com/plyint/encpass.sh
########################################################################################################################

########################################################################################################################
# INCLUDES #############################################################################################################
########################################################################################################################

# use the encpass script to securely store secrets
. encpass-lite.sh

########################################################################################################################
# SECRETS ##############################################################################################################
########################################################################################################################

# specify the name of the nextcloud database
nextcloudDB=$(get_secret nextcloud db)

# specify the user to access the nextcloud database
nextcloudDBUser=$(get_secret nextcloud dbUser)

# set the password to authenticate the above defined user
nextcloudDBPassword=$(get_secret nextcloud dbPassword)

########################################################################################################################
# VARIABLES ############################################################################################################
########################################################################################################################

# create backup directories under the backupRoot with a timestamp
backupRoot='/mnt/backup/nextcloud'
currentDate=$(date +"%Y%m%d_%H%M%S")
backupDirectory="${backupRoot}/${currentDate}/"

# specify the location of the nextcloud installation directory
nextcloudInstallationDirectory='/var/www/nextcloud'

# specify the location of the nextcloud data directory
nextcloudDataDirectory='/home/nextcloud/data'

# define whether to use compression or not (see notes above)
useCompression=false

# specify the name of the web server or reverse proxy user
webServerService='nginx'

# specify the web server user
webServerUser='www-data'

# specify the database: can either be mysql, mariadb, postgresql
database='postgresql'

# define the number of backups to keep, if set to 0, all backups are kept
nBackupsToKeep=7

# define file names for the backups
fnBackupInstallationDirectory='nextcloud-installation-directory.tar'
fnBackupDataDirectory='nextcloud-data-directory.tar'

if [ "$useCompression" = true ]; then
  fnBackupInstallationDirectory="${fnBackupInstallationDirectory}.gz"
  fnBackupDataDirectory="${fnBackupDataDirectory}.gz"
fi

fnBackupDB='nextcloud-db.dump'

########################################################################################################################
# METHODS ##############################################################################################################
########################################################################################################################

# print error messages
errorecho() { cat <<<"$@" 1>&2; }

# disable NextCloud maintenance mode
function disableMaintenanceMode() {
  #echo "Disabling maintenance mode ..."
  sudo -u "${webServerUser}" php ${nextcloudInstallationDirectory}/occ maintenance:mode --off
  #echo "Done"
  echo
}

# capture CTRL+C input and optionally restart the nextcloud instance before quitting
trap CtrlC INT

function CtrlC() {
  # ask user for confirmation
  read -p "Cancelling Backup ... Stay in Maintenance Mode? [y/n] " -n 1 -r
  echo

  if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    disableMaintenanceMode
  else
    echo "Warning: Maintenance Mode still enabed!"
  fi

  echo "Restarting the web server ..."
  systemctl start "${webServerService}"
  echo "Done"
  echo

  exit 1
}

########################################################################################################################
# SCRIPT ###############################################################################################################
########################################################################################################################

# print starting info
echo
echo "Creating a backup of the NextCloud instance ..."
echo
echo "Backup Directory: ${backupRoot}"
echo "Backup Date: ${currentDate}"
echo
echo

# make sure the script is run as root user
if [ "$(id -u)" != "0" ]; then
  errorecho "Critical Error: The backup script has to be run as root!"
  exit 1
fi

# check for existing directory
if [ ! -d "${backupDirectory}" ]; then
  mkdir -p "${backupDirectory}"
else
  errorecho "Critical Error: The backup directory ${backupDirectory} already exists!"
  exit 1
fi

# set maintenance mode
#echo -n "Enabling NextCloud Maintenance Mode ..."
sudo -u "${webServerUser}" php ${nextcloudInstallationDirectory}/occ maintenance:mode --on
#echo "Done"
echo

# stop the web server (reverse proxy)
echo -n "Stopping the web server ..."
systemctl stop "${webServerService}"
echo " done"

# backup the installation directory
echo -n "Creating backup of the NextCloud installation directory ..."

if [ "$useCompression" = true ]; then
  tar --create --preserve-permissions --gzip --file="${backupDirectory}/${fnBackupInstallationDirectory}" --directory="${nextcloudInstallationDirectory}" .
else
  tar --create --preserve-permissions --file="${backupDirectory}/${fnBackupInstallationDirectory}" --directory="${nextcloudInstallationDirectory}" .
fi

echo " done"

# backup the NextCloud data directory
echo -n "Creating backup of the NextCloud data directory ..."

if [ "$useCompression" = true ]; then
  tar --create --preserve-permissions --gzip --file="${backupDirectory}/${fnBackupDataDirectory}" --directory="${nextcloudDataDirectory}" .
else
  tar --create --preserve-permissions --file="${backupDirectory}/${fnBackupDataDirectory}" --directory="${nextcloudDataDirectory}" .
fi

echo " done"

# backup the NextCloud DB
if [ "${database,,}" = "mysql" ] || [ "${database,,}" = "mariadb" ]; then
  # MariaDB or MySQL dump
  echo -n "Dumping the Nextcloud DB (MySQL / MariaDB) ..."

  if ! [ -x "$(command -v mysqldump)" ]; then
    errorecho "Critical Error: MySQL / MariaDB not installed (command mysqldump not found)!"
    errorecho "Critical Error: Unable to dump the NextCloud DB!"
  else
    mysqldump --single-transaction -h localhost -u "${nextcloudDBUser}" -p"${nextcloudDBPassword}" "${nextcloudDB}" > "${backupDirectory}/${fnBackupDB}"
  fi

  echo " done"
elif [ "${database,,}" = "postgresql" ] || [ "${database,,}" = "pgsql" ]; then
  echo -n "Dumping the NextCloud DB (PostgreSQL) ..."

  if ! [ -x "$(command -v pg_dump)" ]; then
    errorecho "Critical Error: PostgreSQL not installed (command pg_dump not found)!"
    errorecho "Critical Error: Unable to dump the NextCloud DB!"
  else
    pg_dump --host=localhost --port=5432 --dbname="${nextcloudDB}" --username="${nextcloudDBUser}" --no-password --file="${backupDirectory}/${fnBackupDB}"
  fi

  echo " done"
fi

# restart the web server
echo -n "Restarting the web server ..."
systemctl start "${webServerService}"
echo " done"
echo

# disabling maintenance mode
disableMaintenanceMode

# delete old backups
if ((nBackupsToKeep != 0)); then
  # get number of backup directories
  nBackups=$(find $backupRoot -mindepth 1 -maxdepth 1 -type d | wc -l)

  if ((nBackups > nBackupsToKeep)); then
    echo "Removing old backups ..."
    echo

    # remove old backup directories
    find $backupRoot -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%p\0' | sort --zero-terminated --numeric-sort --reverse | tail --zero-terminated --lines=$((nBackups - nBackupsToKeep >= 0 ? nBackups - nBackupsToKeep : 0)) | xargs --null --no-run-if-empty --max-args=1 echo | cut --fields=2 | xargs --no-run-if-empty rm -rf --verbose
  fi
fi

echo
echo "The Backup of the NextCloud instance was successful!"
echo
echo "Created Backup: ${backupDirectory}"
if [ "$useCompression" = false ]; then
  echo "This Backup can now be assimilated by the Borg!"
fi