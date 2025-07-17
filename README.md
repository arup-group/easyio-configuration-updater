# EASYIO CONFIGURATION UPDATER

This project provides tools intended to be used in conjunction with the JCI EasyIO project backup
and restore utilities for EasyIO BMS controller products.

Specifically, the updater tools:

1. Identify the most recent backup associated with a particular device in the backup and
download workflow.

2. Find the principal or gateway device name and (optionally) create new keys.

3. Expand the compressed .tgz archive of the controller.
 
4. Update the TLS keys used for MQTT communications.

5. Update the MQTT configuration.

6. Update the time settings to use UTC with no daylight savings time.

6. Re-archive the updated files and prepares the backups for an upload and restore workflow.

## System requirements

To benefit from the tools in this project, you need to have the EMS package from JCI, which
manages backup and restoration of configuration files from EasyIO devices. These tools are
supported to run on a Windows computer. You'll also need one or more EasyIO controller devices
to test the workflow from end-to-end.

The project runs in a command line or terminal environment. Windows computers need to have Git
for Windows, MSYS2 or WSL installed to use the bash shell script version. Alternatively, the
transliterated Powershell version can run in a Powershell session.

## Example workflow

The commandline example presented assumes that `batch_tools` within the EMS installation is
the working directory, and these scripts are installed/added locally there.

To install the scripts:
```
git clone https://github.com/arup-group/easyio-configuration-updater.git
```

The `easyio_key_generator.sh` script will scan the backup automation directory for backup
files and create new keys in the supplied directory. To reduce over-writing risks, the script
will exit if this destination is not empty of keys.

The `easyio_configuration_updater.sh` script will scan the download directory for backup files
and create an expansion of each archive in the supplied output directory. Using the supplied
keys directory, it will install new keys in the appropriate location in the backup path and
edit the `data_mapping.json` file in the `DataServiceConfig` folder. It will also update the
`time.dat` file within the `firmware_data.tar` file. Finally it will re-archive the edited
backup ready for upload and restore to the controller.

The four steps below are:
- Create and download backup files from controllers
- Create new keys using device name information in backup files
- Install keys and other updates in an altered version of each backup file
- Upload backup files and restore

Bash shell:
```
./BatchWorker.exe -project 01_backup_and_download 01_backup_and_download.yml
mkdir data/projects/new_keys_directory
easyio-configuration-updater/easyio_key_generator.sh data/projects/01_backup_and_download data/projects/new_keys_directory
easyio-configuration-updater/easyio_configuration_updater.sh data/projects/01_backup_and_download data/projects/02_upload_and_restore data/projects/new_keys_directory
./BatchWorker.exe -project 02_upload_and_restore 02_upload_and_restore.yml
```

Powershell:
```
.\BatchWorker.exe -project 01_backup_and_download 01_backup_and_download.yml
mkdir data\projects\new_keys_directory
easyio-configuration-updater\easyio_key_generator.ps1 data\projects\01_backup_and_download data\projects\new_keys_directory
easyio-configuration-updater\easyio_configuration_updater.ps1 data\projects\01_backup_and_download data\projects\02_upload_and_restore data\projects/new_keys_directory
.\BatchWorker.exe -project 02_upload_and_restore 02_upload_and_restore.yml
```

If existing keys are to be retained, the step to generate new keys is omitted, and the parameter that references the new keys directory is omitted in the subsequent step. Proceed as follows:

Bash shell:
```
./BatchWorker.exe -project 01_backup_and_download 01_backup_and_download.yml
easyio-configuration-updater/easyio_configuration_updater.sh data/projects/01_backup_and_download data/projects/02_upload_and_restore
./BatchWorker.exe -project 02_upload_and_restore 02_upload_and_restore.yml
```

Powershell:
```
.\BatchWorker.exe -project 01_backup_and_download 01_backup_and_download.yml
easyio-configuration-updater\easyio_configuration_updater.ps1 data\projects\01_backup_and_download data\projects\02_upload_and_restore
.\BatchWorker.exe -project 02_upload_and_restore 02_upload_and_restore.yml
```
