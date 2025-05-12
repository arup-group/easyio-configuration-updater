#!/bin/bash
#
# VERSION: 0.2
#
# Key and config rotator for EasyIO devices
# This script loops over a directory of backup files and puts modified backup files
# into an output directory
#


script_name=$(basename "$0")

# Check that commandline arguments are provided
if [[ $# -ne 3 ]]; then
    echo "Usage: $script_name [backup_project_directory] [output_project_directory] [keys_directory]"
    exit 1
fi

# Now, check that the provided directory paths all exist
for dir in "$@"; do
    if [[ ! -d $dir ]]; then
        echo "$dir does not exist, quitting."
        exit 1
    fi
done

backup_directory="$1"
output_directory="$2"
keys_directory="$3"


update_cloud_settings () {
     # parameter: root directory of expanded backup
     $configuration_path="$1/cpt/plugins/DataServiceConfig"
     sed_substitution_script='s/\"essential-keep-197822\"/\"bos-platform-prod\"/g; \
                              s/\"mqtt.googleapis.com\"/\"mqtt.bos.goog\"/g; \
                              s/\"rsa_(private|public)[A-Z0-9]*\.pem\"/\"rsa_\1.pem\"/g' 
     mv "$configuration_path/data_mapping.json" "$configuration_path/data_mapping.old.json"
     cat "$configuration_path/data_mapping.old.json" \
        | sed -E "$sed_substitution_script" > "$configuration_path/data_mapping.json"
     rm "$configuration_path/data_mapping.old.json"
}


update_keys () {
     # parameters: root directory of expanded backup, BOS name of controller device
     $keys_path="$1/cpt/plugins/DataServiceConfig/uploads/certs"
     $private_key="$2_private.pem"
     $public_key="$2_public.pem"
     $ca_file=""
     # Update the certificate, private key and CA file
     rm "$keys_path"/*
     cp "$keys_source_directory/$private_key" "$keys_path/$private_key" \
         && cp "$keys_source_directory/$public_key" "$keys_path/$public_key" \
         && cp "$keys_source_directory/$ca_file" "$keys_path/$ca_file" \
     || echo "ERROR: Failed to copy key files."
}

# Identify device
# grep -oE '"device_id":"[^"]+"' data_mapping.json | head -n 1 | sed -E 's/"device_id":"(.*)"/\1/'

# Iterate through the list of device directories, which are expected in the form of IPv4 addresses, one per device
echo "Processing EasyIO backup files in $backup_directory..."

for device_directory in $backup_directory/*; do
    # find just the final part of the path 
    device_directory=$(basename "$device_directory")
    # continue to the next device if there is no device backup directory
    # or it is in the wrong format
    [[ -d "$backup_directory/$device_directory" && \
        "$device_directory" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    echo -n "Found device $device_directory"
    # This shell syntax creates an array of all the files that match the pattern
    set -- $backup_directory/$device_directory/*.tgz
    # and we collect the name of just the final file in the list
    latest_backup=$(basename "${!#}") 
    # check the file is a regular file
    if [[ -f "$backup_directory/$device_directory/$latest_backup" ]]; then
        echo ": using backup $latest_backup"
        # expand the backup
        tar xfz "$backup_directory/$device_directory/$latest_backup"
        # compress the backup
        tar cfz "$output_directory/$device_directory/updated_$latest_backup" "$expanded_root_dir" 
        
    else
        echo ": WARNING no backup file found for $latest_backup!"
    fi     
done


echo "Finished."

