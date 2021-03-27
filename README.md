# Backup and Restore NextCloud Instances
The two bash scripts in this repository can be used to back up or restore a [NextCloud](https://nextcloud.com/) instance. They were inspired by [DetaTec](https://codeberg.org/DecaTec/Nextcloud-Backup-Restore). The main differences are the use of [EncPass](/bell0bytes/scripts/encpass) to hide secrets, and the replacement of **ls** calls by the **find** command, thus simplifying the code to remove old backups.

The scripts must be configured by defining a few variables in the **VARIABLES** sections.

## NextCloud Directories and Database Type
To backup/restore a NextCloud instance, two directories and a database must be backed up or restored. Those values can be set in the **VARIABLES** section of the scripts, i.e.

```bash
# specify the location of the nextcloud installation directory
nextcloudInstallationDirectory='/var/www/nextcloud'

# specify the location of the nextcloud data directory
nextcloudDataDirectory='/home/nextcloud/data'

# specify the database: can either be mysql, mariadb, postgresql
database='postgresql'
```

#### NextCloud Installation Directory
This is the installation directory of NextCloud, which can usually be found within the web directory of a server. The default is set to **/var/www/nextcloud**.

#### NextCloud Data Directory
This is the working or data directory of NextCloud. The default is set to **/home/nextcloud/data**.

#### NextCloud Database
To dump the NextCloud database, and to import that dump again, later on, the script needs to know which database is used. The default is set to **postgresql**, i.e. a PostgreSQL database is used.

**Warning**: The script assumes that the database was created with **UTF-8** supprt.

## Secrets and EncPass
To avoid storing secrets in a script, most bell0bytes scripts use [EncPass](/bell0bytes/scripts/encpass).

The backup and restore scripts require the following information:
* **nextcloudDB**: the name of the NextCloud database
* **nextcloudDBUser**: the user to access the database specified above
* **nextCloudDBPassword**: the password to authenticate the above specified user with

Before starting the scripts, one must thus make sure that those secrets actually exists. A list of secrets for a given bucket can be shown with the **list** command, as follows:

```
sudo encpass.sh list nextcloud
```

If the output looks like this, everything is fine:

```
db
dbPassword
dbUser
```

If not, the secrets have to be created:
```
sudo encpass.sh add nextcloud db
sudo encpass.sh add nextcloud dbUser
sudo encpass.sh add nextcloud dbPassword
```

**Note**: Since the backup script must be run as root, the EncPass secrets must also be created for the root user, hence the use of sudo.

## Further Configuration
The following variables should be set to adapt the script to the environment in question.
| Variable | Description | Default |
| :------- | :---------- | :------ |
| backupRoot | the root directory for the backups | /mnt/backup/nextcloud |
| useCompression | true iff compression should be used | false |
| webServerService | the name of the web or proxy server | nginx |
| webServerUser | the web user | www-data |
| nBackupsToKeep | the number of backups to keep | 7 |
| fnBackupInstallationDirectory | the name of the backup file for the installation directory | nextcloud-installation-directory.tar |
| fnBackupDataDirectory | the name of the backup file for the data directory | nextcloud-data-directory.tar |
| fnBackupDB | the name of the backup file for the database dump | nextcloud-db.dump |

**NB 1**: If **useCompression** is set to **true**, **.gz** will be appended to the file names.

**NB 2**: If another backup software, such as Borg, is to be used, compression should be disabled.

## Automation with Cronjobs
I suggest running the backup script each evening and keeping $7$ backups. To do so, a cronjob must be created for the root user.

```
sudo crontab -e
```

```
0 5 * * * /bin/bash '/home/symplectos/Scripts/Backup/NextCloud/nextcloudBackup.sh'
```

**Note**: Make sure the script is executable.

## Manual Usage

### Backup
Simply run the backup script with superuser do:

```
sudo ./nextcloudBackup.sh
```

### Restore
To restore a backup, run the script, with superuser do, specifying the desired backup to restore as parameter:

```
sudo ./nextcloudRestore.sh 20210325_050000
```

## Test Run
Test run with **nBackupsToKeep=1** and **useCompression=false**:

```
sudo ./nextcloudBackup.sh

Creating a backup of the NextCloud instance ...

Backup Directory: /mnt/backup/nextcloud
Backup Date: 20210327_200514


Maintenance mode enabled

Stopping the web server ... done
Creating backup of the NextCloud installation directory ... done
Creating backup of the NextCloud data directory ... done
Dumping the NextCloud DB (PostgreSQL) ... done
Restarting the web server ... done

Maintenance mode disabled

Removing old backups ...

removed '/mnt/backup/nextcloud/20210327_200421/nextcloud-installation-directory.tar'
removed '/mnt/backup/nextcloud/20210327_200421/nextcloud-data-directory.tar'
removed '/mnt/backup/nextcloud/20210327_200421/nextcloud-db.sql'
removed directory '/mnt/backup/nextcloud/20210327_200421'

The Backup of the NextCloud instance was successful!

Created Backup: /mnt/backup/nextcloud/20210327_200514/
This Backup can now be assimilated by the Borg!
```

To restore this backup, the **20210327_200514** should be given as a parameter to the restore script:

```
sudo ./nextcloudRestore.sh 20210327_200514
```

# References
* [DetaTec](https://codeberg.org/DecaTec)
* [EncPass](https://github.com/plyint/encpass.sh)
* [NextCloud](https://docs.nextcloud.com/server/21/admin_manual/)