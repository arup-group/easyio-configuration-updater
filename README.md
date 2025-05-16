# EASYIO CONFIGURATION UPDATER

This project provides tools intended to be used in conjunction with the JCI EasyIO project backup
and restore utilities for EasyIO BMS controller products.

Specifically, the updater tool:

1. Identifies the most recent backup associated with a particular device in the backup and
download workflow.

2. Expands the compressed .tar archive.
 
3. Updates the TLS keys used for MQTT communications.

5. Updates the MQTT configuration.

6. Archives the updated files and prepares them for an upload and restore workflow.

## System requirements

To benefit from the tools in this project, you need to have the EMS package from JCI, which
manages backup and restoration of configuration files from EasyIO devices. These tools are
supported to run on a Windows computer. You'll also need one or more EasyIO controller devices
to test the workflow from end-to-end.

The project runs in a command line or terminal environment. Windows computers need to have Git
for Windows, MSYS2 or WSL installed to use the bash shell script version. Alternatively, the
transliterated Powershell version can run in a Powershell window.

## Examples

### To generate new keys for a group of EasyIO devices

This script will scan the automation directory for backup files and create new keys in the
supplied directory. The destination must be empty of keys, to avoid mistakes. 

```./easyio_key_generator.sh backups_directory new_keys_directory```

### To install keys and updates to cloud configuration file

This script will scan the automation directory for backup files and create an expansion of
each archive in the supplied output directory. Using the supplied keys directory, it will
install new keys in the appropriate location in the backup path and also edit the
```data_mapping.json``` file in the ```DataServiceConfig``` folder. Finally it will re-archive
the edited backup ready for upload and restore to the controller.

```./easyio_configuration_updater.sh backups_directory updated_backups_directory keys_directory```



