#!/bin/bash
#
# VERSION: 0.11 FOR TESTING!
#
# Key and config rotator for EasyIO devices
# This script loops over a directory of backup files and puts modified backup files
# into an output directory
#
# Example invocation:
# ./easyio_rotator.sh backups outputs new_keys
#

# Check that commandline arguments are provided
if [[ $# -ne 3 ]]; then
    echo "Usage: easyio_rotator.sh [input_directory] [output_directory] [keys_directory]"
    exit 1
fi

# Now, check that the provided directory paths all exist
for dir in "$@"; do
    if [[ ! -d $dir ]]; then
        echo "$dir does not exist, quitting."
        exit 1
    fi
done

# NB In the keys_directory, there should be rsa_public.pem, rsa_private.pem and 'CA File.pem'. We use the same keys for all devices.
backup_directory=$1
output_directory=$2
keys_directory=$3

echo "Processing EasyIO backup files in $backup_directory..."

for backup_path in "$backup_directory"/*tgz; do
    # Unzip the backup
    tar xfz "$backup_path"
    
    # Get the root directory of the expanded archive
    backup_file=$(basename "$backup_path")
    [[ "$backup_file" =~ [FW|FS]-([0-9]+_backup)s*.tgz ]]
    expanded_root_dir="${BASH_REMATCH[1]}"
    key_destination="$expanded_root_dir/cpt/plugins/DataServiceConfig/uploads/certs"
    config_destination="$expanded_root_dir/cpt/plugins/DataServiceConfig"

    # Update the config file
    mv "$config_destination/data_mapping.json" "$config_destination/data_mapping.old.json"
    cat "$config_destination"/data_mapping.old.json | sed -E 's/"essential-keep-197822"/"bos-platform-prod"/g; s/"mqtt.googleapis.com"/"mqtt.bos.goog"/g; s/"rsa_(private|public)[A-Z0-9]*\.pem"/"rsa_\1.pem"/g' > "$config_destination/data_mapping.json"
    rm "$config_destination/data_mapping.old.json"
    
    # Update the certificate, private key and CA file
    rm "$key_destination"/*
    for key in "$keys_directory"/*; do
        cp "$key" "$key_destination"
    done
 
    # Make a new tar file ready for restore, then get rid of working directory
    tar cfz "$output_directory/$backup_file" "$expanded_root_dir" 
    rm -rf "$expanded_root_dir" 

    echo "$backup_path --> $output_directory/$backup_file"
    
done

echo "Finished."

