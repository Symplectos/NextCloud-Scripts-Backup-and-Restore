#!/bin/bash

########################################################################################################################
# Bash script to restore NextCloud instance from a Backup
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
# Usage:
#   - ./nextcloudRestore.sh <backup> (i.e. ./nextcloudRestore.sh 20210315_050000)
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

# get backup to restore (by date)
restore=$1
backupRoot='/mnt/backup/nextcloud'
restorationDirectory="${backupRoot}/${restore}"

# specify the location of the nextcloud installation directory
nextcloudInstallationDirectory='/var/www/nextcloud'

# specify the location of the nextcloud data directory
nextcloudDataDirectory='/home/nextcloud/data'

# define whether to use compression or not (see notes above)
useCompression=true

# specify the name of the web server or reverse proxy user
webServerService='nginx'

# specify the web server user
webServerUser='www-data'

# specify the database: can either be mysql, mariadb, postgresql
database='postgresql'

# backup file names as defined in the backup script
fnBackupInstallationDirectory='nextcloud-installation-directory.tar'
fnBackupDataDirectory='nextcloud-data-directory.tar'

if [ "$useCompression" = true ] ; then
    fnBackupInstallationDirectory='nextcloud-installation-directory.tar.gz'
    fnBackupDataDirectory='nextcloud-data-directory.tar.gz'
fi

fnBackupDB='nextcloud-db.sql'

########################################################################################################################
# CHECKS ###############################################################################################################
########################################################################################################################

# print error messages
errorecho() { cat <<< "$@" 1>&2; }

# check for valid parameters
if [ $# != "1" ]
then
    errorecho "Critical Error: Please specify the Backup to restore!"
    errorecho "Usage: ./nextcloudRestore.sh 'BackupDate'"
    exit 1
fi

# make sure the script is run as root user
if [ "$(id -u)" != "0" ]
then
    errorecho "Critical Error: The backup script has to be run as root!"
    exit 1
fi

# check for valid directory
if [ ! -d "${restorationDirectory}" ]
then
    errorecho "Critical Error: Backup ${restore} not found!"
    exit 1
fi

# check for DB installation
if [ "${database,,}" = "mysql" ] || [ "${database,,}" = "mariadb" ]; then
    if ! [ -x "$(command -v mysql)" ]; then
        errorecho "Critical Error: MySQL / MariaDB not installed (command mysql not found)."
        errorecho "Critical Error: Unable to restore DB!"
        errorecho "The restoration was cancelled!"
        exit 1
    fi
elif [ "${database,,}" = "postgresql" ] || [ "${database,,}" = "pgsql" ]; then
    if ! [ -x "$(command -v psql)" ]; then
        errorecho "Critical Error: PostgreSQL not installed (command psql not found)."
        errorecho "Critical Error: Unable to restore DB!"
        errorecho "The restoration was cancelled!"
        exit 1
    fi
fi

########################################################################################################################
# SCRIPT ###############################################################################################################
########################################################################################################################

# echo starting message
echo
echo "Restoring Backup: $restorationDirectory"
echo

# set maintenance mode
sudo -u "${webServerUser}" php ${nextcloudInstallationDirectory}/occ maintenance:mode --on

# stop the web server (reverse proxy)
echo -n "Stopping the web server ..."
systemctl stop "${webServerService}"
echo " done"


# delete old installation directory
echo "Deleting the old NextCloud installation directory ..."
rm -r "${nextcloudInstallationDirectory}"
mkdir -p "${nextcloudInstallationDirectory}"
echo " done"

# delete old data directory
echo -n "Deleting the old NextCloud data directory ..."
rm -r "${nextcloudDataDirectory}"
mkdir -p "${nextcloudDataDirectory}"
echo " done"


# restore installation directory
echo -n "Restoring the NextCloud installation directory ..."

if [ "$useCompression" = true ] ; then
    tar -xmpzf "${restorationDirectory}/${fnBackupInstallationDirectory}" -C "${nextcloudInstallationDirectory}"
else
    tar -xmpf "${restorationDirectory}/${fnBackupInstallationDirectory}" -C "${nextcloudInstallationDirectory}"
fi

echo " done"

# restore data directory
echo -n "Restoring the NextCloud data directory ..."

if [ "$useCompression" = true ] ; then
    tar -xmpzf "${restorationDirectory}/${fnBackupDataDirectory}" -C "${nextcloudDataDirectory}"
else
    tar -xmpf "${restorationDirectory}/${fnBackupDataDirectory}" -C "${nextcloudDataDirectory}"
fi

echo " done"

# restore the DB
echo -n "Dropping the old NextCloud DB ..."

if [ "${database,,}" = "mysql" ] || [ "${database,,}" = "mariadb" ]; then
    mysql -h localhost -u "${nextcloudDBUser}" -p"${nextcloudDBPassword}" -e "DROP DATABASE ${nextcloudDB}"
elif [ "${database,,}" = "postgresql" ]; then
    sudo -u postgres psql -c "DROP DATABASE ${nextcloudDB};"
fi

echo " done"

echo -n "Creating the new NextCloud DB ..."

if [ "${database,,}" = "mysql" ] || [ "${database,,}" = "mariadb" ]; then
    mysql -h localhost -u "${nextcloudDBUser}" -p"${nextcloudDBPassword}" -e "CREATE DATABASE ${nextcloudDB} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"
elif [ "${database,,}" = "postgresql" ] || [ "${database,,}" = "pgsql" ]; then
    sudo -u postgres psql -c "CREATE DATABASE ${nextcloudDB} WITH OWNER ${nextcloudDBUser} TEMPLATE template0 ENCODING \"UTF8\";"
fi

echo " done"

echo "Importing the DB dump into the new DB ..."

if [ "${database,,}" = "mysql" ] || [ "${database,,}" = "mariadb" ]; then
    mysql -h localhost -u "${nextcloudDBUser}" -p"${nextcloudDBPassword}" "${nextcloudDB}" < "${restorationDirectory}/${fnBackupDB}"
elif [ "${database,,}" = "postgresql" ] || [ "${database,,}" = "pgsql" ]; then
    psql -U"${nextcloudDBUser}" "${nextcloudDB}" < "${restorationDirectory}/${fnBackupDB}"
fi

echo " done"

# restart the web server
echo -n "Restarting the web server ..."
systemctl start "${webServerService}"
echo " done"

# reset directory permissions
echo -n "Chowning the correct directory permissions ..."
chown -R "${webServerUser}":"${webServerUser}" "${nextcloudInstallationDirectory}"
chown -R "${webServerUser}":"${webServerUser}" "${nextcloudDataDirectory}"
echo " done"

# update the system data fingerprint (see https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html#maintenance-commands-label)
echo -n "Updating the System Data-Fingerprint ..."
sudo -u "${webServerUser}" php ${nextcloudInstallationDirectory}/occ maintenance:data-fingerprint
echo " done"
echo

# disable maintenance mode
#echo "Disabling NextCloud Maintenance Mode ..."
sudo -u "${webServerUser}" php ${nextcloudInstallationDirectory}/occ maintenance:mode --off
#echo "Done"

echo
echo "Done: The Backup ${restore} was successfully restored!"