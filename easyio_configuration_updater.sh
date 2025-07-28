#!/bin/bash
#
# VERSION: 0.6
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

backup_directory="$1"
output_directory="$2"
key_source_directory="$3"


identify_device_names () {
    # parameter, path to expanded archive
    parameter_file="$1/cpt/plugins/DataServiceConfig/data_mapping.json"
    # find key:value pairs with device_id as key, then filter for the
    # first one (which is the controller name)
    all_device_names=$(grep -oE '"device_id":"[^"]+"' "$parameter_file" \
        | sed -E 's/"device_id":"(.*)"/\1/' | readarray -t)
    device_name=${all_device_names[0]}
}

update_cloud_settings () {
    # parameters: root directory of expanded backup, BOS name of controller device
    # the name of the keys for each virtual device take the following form
    # EXISTING
    # "ca_file":"CA File.pem"
    # "key_file":"rsa_private_DEV-0000.pem"
    # "cert_file":"rsa_public_DEV-0000.pem"
    # NEW
    # "ca_file":"CA File.pem"
    # "key_file":"rsa_private_DEV-0000.pem"
    # "cert_file":"rsa_cert_DEV-0000.pem" 
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
    # parameters: root directory of expanded backup, BOS name of controller and proxy devices
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

update_time_settings () {
    # parameter: root directory of expanded backup
    # sets the time configuration to use UTC with no daylight savings time
    read -r -d '' new_time_dot_dat << _EOF_
UTC Offset:0
Time Zone:Etc/UTC
DST Offset:0
DST Start On:-1
DST Start Date:1,0
DST Start Time:0,0
DST End On:-1
DST End Date:1,0
DST End Time:0,0
_EOF_
    # expand the firmware.tar file into a temporary directory
    # replace the time.dat file with the contents of the heredoc
    # then recompress the firmware.tar file and remove the temporary directory.
    mkdir "$1/firmware_data" \
    && tar -x -C "$1/firmware_data" -f "$1/firmware_data.tar" \
    && printf "%s\n" "$new_time_dot_dat" > "$1/firmware_data/time.dat" \
    && tar -cf "$1/firmware_data.tar" -C "$1/firmware_data" . \
    && rm -r "$1/firmware_data" \
    || echo "ERROR: Failed to update time.dat file." 1>&2
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

        # Update settings, keys and time configuration
        # we use the $? status code to short-circuit in case of failure of the update
        identify_device_name "$output_directory/$device_directory/$expanded_root_dir" \
            && update_cloud_settings "$output_directory/$device_directory/$expanded_root_dir" "$device_name" \
            && update_keys "$output_directory/$device_directory/$expanded_root_dir" "$all_device_names" \
            && update_time_settings "$output_directory/$device_directory/$expanded_root_dir" \
            || (echo "ERROR: Failed to update $device_directory." && continue)

        # Rename and compress the backup, and delete the expansion
        mv "$output_directory/$device_directory/$expanded_root_dir" "$output_directory/$device_directory/updated_backup" \
            && tar -czf "$output_directory/$device_directory/updated_backup.tgz" \
                -C "$output_directory/$device_directory" "updated_backup" \
            && rm -r "$output_directory/$device_directory/updated_backup" \
            || echo "ERROR: Failed to create the output archive." 1>&2

        echo "$backup_directory/$device_directory/$latest_backup  -> " \
             "$output_directory/$device_directory/updated_backup.tgz"
    else
        echo "WARNING no backup file found for $backup_directory/$device_directory, skipping!" 1>&2 
    fi     
done


echo "Finished."

