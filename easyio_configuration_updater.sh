#!/bin/bash
#
# VERSION: 0.2
#
# Key and config rotator for EasyIO devices
# This script loops over a directory of backup files and puts modified backup files
# into an output directory
# TLS KEYS MUST BE GENERATED BEFORE RUNNING THIS SCRIPT
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

# Store directory names, removing any trailing slash
backup_directory="${1%/}"
output_directory="${2%/}"
key_source_directory="${3%/}"


identify_device_name () {
    # parameter, path to expanded archive
    parameter_file="$1/cpt/plugins/DataServiceConfig/data_mapping.json"
    # find key:value pairs with device_id as key, then filter for the
    # first one (which is the controller name)
    device_name=$(grep -oE '"device_id":"[^"]+"' "$parameter_file" \
        | head -n 1 \
        | sed -E 's/"device_id":"(.*)"/\1/')
}


update_cloud_settings () {
    # parameters: root directory of expanded backup, BOS name of controller device
    # function returns 0 on success
    configuration_path="$1/cpt/plugins/DataServiceConfig"
    device_name="$2"
    sed_substitution_script="s/\"essential-keep-197822\"/\"bos-platform-prod\"/g; s/\"mqtt.googleapis.com\"/\"mqtt.bos.goog\"/g; s/\"rsa_private[A-Z0-9]*\.pem\"/\"rsa_private$device_name.pem\"/g; s/\"rsa_public[A-Z0-9]*\.pem\"/\"rsa_public$device_name.pem\"/g" 
    # using a temporary file, apply stream editor to the configuration file
    mv "$configuration_path/data_mapping.json" "$configuration_path/data_mapping.old.json" \
        && sed -E "$sed_substitution_script" "$configuration_path/data_mapping.old.json" \
            > "$configuration_path/data_mapping.json" \
        && rm "$configuration_path/data_mapping.old.json"
}

update_keys () {
    # parameters: root directory of expanded backup, BOS name of controller device
    # function returns 0 on success
    keys_path="$1/cpt/plugins/DataServiceConfig/uploads/certs"
    private_key="rsa_private$2.pem"
    public_key="rsa_public$2.pem"
    ca_file="CA File.pem"
    # Update the certificate, private key and CA file
    # delete old keys
    [[ -d "$keys_path" ]] && rm "$keys_path"/*
    # copy new ones from the keys source directory
    cp "$key_source_directory/$private_key" "$keys_path/$private_key" \
        && cp "$key_source_directory/$public_key" "$keys_path/$public_key" \
        && cp "$key_source_directory/$ca_file" "$keys_path/$ca_file" \
        || echo "ERROR: Failed to copy key files." 1>&2
}


# Iterate through the list of device directories, which are expected in the form of IPv4 addresses, one per device
echo "Processing EasyIO backup files in $backup_directory..."

# Loop through all the device directories in turn and process the backups:
# a corresponding device directory is created in the output directory with
# modified backup files
for device_directory in $backup_directory/*; do
    # find just the final part of the path 
    device_directory=$(basename "$device_directory")
    # continue to the next device if there is no device backup directory
    # or it is in the wrong format
    [[ -d "$backup_directory/$device_directory" && \
        "$device_directory" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    # This shell syntax creates a bash parameter array of all the files that match the pattern
    set -- $backup_directory/$device_directory/*.tgz
    # and we collect the name of just the final file in the list, the ! allows indirect variable
    # expansion on the final parameter in the array, whose number is #. The upshot is that we
    # should have selected at this point the most recent backup file if they are named in datetime
    # order.
    latest_backup=$(basename "${!#}") 
    # confirm that the selected file is a regular file, not a link, directory or wildcard
    if [[ -f "$backup_directory/$device_directory/$latest_backup" ]]; then

        # make a directory for the device in the output directory
        # if it doesn't already exist
        [[ -d "$output_directory/$device_directory" ]] \
            || mkdir "$output_directory/$device_directory" \
            || echo "ERROR: Failed to create $output_directory/$device_directory." 1>&2

        # Expand the backup into the output directory
        tar -xz -C "$output_directory/$device_directory" \
            -f "$backup_directory/$device_directory/$latest_backup" 

        # Find the name of the root directory of the expanded backup
        for file in $output_directory/$device_directory/*; do 
            # It just grabs the name of the first directory it can find
            [[ -d "$file" ]] && expanded_root_dir=$(basename "$file") && break
        done

        # Update settings and keys
        # we use the $? status code to short-circuit in case of failure of the update
        identify_device_name "$output_directory/$device_directory/$expanded_root_dir" \
        && update_cloud_settings "$output_directory/$device_directory/$expanded_root_dir" "$device_name" \
        && update_keys "$output_directory/$device_directory/$expanded_root_dir" "$device_name" \
        || (echo "ERROR: Failed to update $device_directory." && continue)

        # Compress the backup and delete the expansion
        tar_file_name="${latest_backup%.tgz}_updated.tgz"
        tar -cz -C "$output_directory/$device_directory" \
            -f "$output_directory/$device_directory/$tar_file_name" "$expanded_root_dir" \
            && rm -r "$output_directory/$device_directory/$expanded_root_dir" \
            || echo "ERROR: Failed to create the output archive." 1>&2

        echo "$backup_directory/$device_directory/$latest_backup  -> " \
             "$output_directory/$device_directory/$tar_file_name"
    else
        echo "WARNING no backup file found for $backup_directory/$device_directory, skipping!" 1>&2 
    fi     
done


echo "Finished."

